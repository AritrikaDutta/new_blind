"""
streamlit_app.py — Sprint 4
============================
Full Streamlit dashboard with:
  • Sidebar CrossingConfig builder
  • Live risk/confidence/tier/FPS metrics panel
  • Browser audio playback (HTML5 autoplay)
  • Local system audio via pygame (when audio_mode = "local")
  • Pipeline reset on new video upload
"""

import streamlit as st
import cv2
import tempfile
import os
import time
import base64
from pathlib import Path

from video_stream_tracking_appmodule import (
    process_frame, fps, reset_pipeline,
    get_current_fps, get_current_tier, get_logger_summary,
    draw_cached_overlays,
)
from crossing_advisor import CrossingConfig
from streamlit_webrtc import webrtc_streamer, WebRtcMode, RTCConfiguration
import av
from voice_feedback_2 import get_last_alert_event

import queue
import threading

class AsyncPipeline:
    def __init__(self, config):
        self.config = config
        self.frame_queue = queue.Queue(maxsize=1)
        self.running = True
        self.thread = threading.Thread(target=self._run_loop, daemon=True)
        self.thread.start()

    def _run_loop(self):
        while self.running:
            try:
                # Wait for a frame to process
                frame = self.frame_queue.get(timeout=0.1)
                # Run the heavy pipeline
                process_frame(frame, self.config)
            except queue.Empty:
                continue
            except Exception as e:
                pass

    def update_frame(self, frame):
        if not self.frame_queue.full():
            try:
                self.frame_queue.put_nowait(frame.copy())
            except queue.Full:
                pass

    def stop(self):
        self.running = False
        if self.thread.is_alive():
            self.thread.join(timeout=1.0)


def fast_frame_display(placeholder, frame_bgr, max_width: int = 640):
    """
    Display a frame fast by encoding it as JPEG and injecting it as HTML.

    st.image() internally encodes numpy arrays as PNG and sends them over
    Streamlit's WebSocket — this takes 150-400ms per frame (2-5 FPS ceiling).

    By encoding to JPEG ourselves and injecting as an HTML <img> tag with a
    base64 data-URL, we bypass that bottleneck entirely. JPEG at quality=80
    takes ~5ms to encode and the browser renders it in <20ms.
    """
    h, w = frame_bgr.shape[:2]
    if w > max_width:
        new_h = int(h * max_width / w)
        frame_bgr = cv2.resize(frame_bgr, (max_width, new_h), interpolation=cv2.INTER_NEAREST)

    _, buf = cv2.imencode('.jpg', frame_bgr, [cv2.IMWRITE_JPEG_QUALITY, 82])
    b64 = base64.b64encode(buf).decode('ascii')
    html = (
        f'<img src="data:image/jpeg;base64,{b64}" '
        f'style="width:100%;border-radius:6px;" />'
    )
    placeholder.markdown(html, unsafe_allow_html=True)


# ─── Page config ─────────────────────────────────────────────────────────────
st.set_page_config(
    page_title = "Pedestrian Safety Assistant",
    page_icon  = "🚦",
    layout     = "wide",
)

st.title("🚦 Pedestrian Safety Assistant")
st.caption("Real-time crossing safety for visually impaired pedestrians — hybrid Physics + AI")

BASE_DIR  = Path(__file__).resolve().parent
AUDIO_DIR = BASE_DIR / "voice_cache"

# ─── Sidebar — CrossingConfig & Accessibility Info ───────────────────────────
with st.sidebar:
    st.header("♿ Accessibility Settings")
    st.markdown(
        """
        **Designed for Pedestrian Navigation Assist**
        
        *   **Voice Alerts**: Speech commands play automatically as traffic is analyzed.
        *   **Local Playback**: Highly recommended for low-latency voice assistance.
        """
    )
    st.divider()

    st.subheader("👤 Pedestrian Settings")
    st.info(
        "Configured with high-safety parameters for visually impaired navigation:\n"
        "- **Walking Speed:** 0.8 m/s (Conservative)\n"
        "- **Safety Margin:** 2.5 s buffer"
    )
    
    # Audio mode selector
    audio_mode = st.radio(
        "Audio Playback Mode",
        ["browser", "local"],
        index=0,
        horizontal=True,
        help="Local mode uses pygame on the host machine for low-latency voice guidance."
    )

    road_width = 8.0
    walk_speed = 0.8
    safety_margin = 2.5
    threat_k = 4
    smooth_frames = 3   # 3 frames ≈ 1.5s at 2 FPS — fast enough to clear when road is safe
    min_conf = 0.65     # Lowered so retreating/stationary vehicles don't block SAFE transition
    use_ego = True
    use_depth = True   # MiDaS_small enabled

    cross_time = road_width / walk_speed
    st.success(
        f"**Active Walk Speed:** {walk_speed} m/s  \n"
        f"**Crossing Time:** {cross_time:.1f} s  \n"
        f"**Safe TTC Limit:** {cross_time + safety_margin:.1f} s"
    )
    st.info(
        "🧠 **MiDaS small** depth model is **active**  \n"
        "Refines physics distance every 3rd frame.  \n"
        "First-frame model load: ~2 s (cached after that)."
    )

# Build config
_config = CrossingConfig(
    road_width_m           = road_width,
    walk_speed_mps         = walk_speed,
    use_ai_depth           = use_depth,
    use_ego_motion         = use_ego,
    threat_rank_k          = threat_k,
    smoothing_frames       = smooth_frames,
    min_confidence_threshold = min_conf,
    audio_mode             = audio_mode,
    safety_margin_sec      = safety_margin,
)

# ─── Pygame local audio init (Sprint 4) ─────────────────────────────────────
_pygame_ready = False
if audio_mode == "local":
    try:
        import pygame
        if not pygame.mixer.get_init():
            pygame.mixer.init()
        _pygame_ready = True
    except ImportError:
        st.sidebar.warning("pygame not installed — falling back to browser audio.")

def _play_local(fpath: str):
    """Play audio file immediately via pygame mixer."""
    if not _pygame_ready:
        return
    try:
        import pygame
        pygame.mixer.music.load(fpath)
        pygame.mixer.music.play()
    except Exception as e:
        st.sidebar.warning(f"Local audio error: {e}")

# ─── Audio / status placeholders ────────────────────────────────────────────
audio_placeholder  = st.empty()
status_placeholder = st.empty()

_LABEL_TO_FILE = {
    "walk_normal":       "walk_normal.mp3",
    "walk_fast":         "walk_fast.mp3",
    "signal_hand_left":  "signal_hand_left.mp3",
    "signal_hand_right": "signal_hand_right.mp3",
    "stop":              "Stop.mp3",
}


def play_alert_if_new():
    """Route audio to browser or local speaker depending on config."""
    evt      = get_last_alert_event()
    last_seq = st.session_state.get("_last_alert_seq", 0)
    if not evt or not evt.get("label"):
        return
    if int(evt.get("seq", 0)) <= int(last_seq):
        return

    st.session_state["_last_alert_seq"] = int(evt.get("seq", last_seq))
    label  = str(evt.get("label", "")).lower()
    fname  = _LABEL_TO_FILE.get(label, "move.mp3")
    fpath  = str((AUDIO_DIR / fname).resolve())

    if not os.path.exists(fpath):
        st.warning(f"Missing audio: {fpath}")
        return

    spoken = evt.get("spoken_text", label)
    seq    = int(evt.get("seq", 0))
    status_placeholder.caption(f"🔊 **{spoken}** *(seq {seq})*")

    if audio_mode == "local" and _pygame_ready:
        _play_local(fpath)
    else:
        try:
            with open(fpath, "rb") as f:
                b64 = base64.b64encode(f.read()).decode("ascii")
            src  = f"data:audio/mpeg;base64,{b64}"
            # Inject raw HTML audio with 'loop' attribute for continuous guidance
            # Using a STATIC id and placing src directly on the <audio> tag ensures 
            # the browser cleanly cuts off the old audio and swaps to the new track.
            html = f'<audio id="safety-alert-audio" src="{src}" autoplay loop playsinline></audio>'
            audio_placeholder.empty()
            audio_placeholder.markdown(html, unsafe_allow_html=True)
        except Exception as e:
            st.warning(f"Browser audio error: {e}")


# ─── Metrics panel (Sprint 4 / Sprint 5) ────────────────────────────────────
_metrics_placeholder = st.empty()

def _render_metrics():
    """Display live FPS, tier, and safety KPIs in a compact row."""
    summary = get_logger_summary()
    tier    = get_current_tier()
    cur_fps = get_current_fps()
    tier_label = {1: "🟢 Full", 2: "🟡 Balanced", 3: "🔴 Fast"}.get(tier, "?")

    with _metrics_placeholder.container():
        c1, c2, c3, c4 = st.columns(4)
        c1.metric("FPS",          f"{cur_fps:.0f}")
        c2.metric("Tier",         tier_label)
        c3.metric("False-Safe",   summary.get("false_safe_count", 0),
                  help="Times system said 'Cross now' when TTC < safe threshold (target: 0)")
        c4.metric("State Switches", summary.get("state_switches", 0),
                  help="Total voice state changes (lower = more stable)")


# ─── Input mode ─────────────────────────────────────────────────────────────
mode = st.radio("Input source:", ["Upload Video", "Live Camera"], horizontal=True)

# ── Upload Video ──────────────────────────────────────────────────────────────
if mode == "Upload Video":
    uploaded = st.file_uploader("Upload a video", type=["mp4", "avi", "mov", "mkv"])

    if uploaded:
        reset_pipeline()   # fresh state for each new video
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".mp4")
        tmp.write(uploaded.read())
        tmp.close()

        cap = cv2.VideoCapture(tmp.name)
        if not cap.isOpened():
            st.error("❌ Could not open the uploaded video.")
        else:
            v_fps = cap.get(cv2.CAP_PROP_FPS)
            _fps  = int(v_fps) if v_fps > 0 else fps

            stframe = st.empty()
            
            # Start background thread for YOLO and safety logic execution
            async_pipeline = AsyncPipeline(_config)
            _display_frame_n = 0

            while cap.isOpened():
                t0 = time.perf_counter()
                _display_frame_n += 1
                
                # Read every frame sequentially to play at correct speed
                ret, frame = cap.read()
                if not ret:
                    break

                # Send frame to background safety processing thread
                async_pipeline.update_frame(frame)

                # Draw the latest processed safety annotations on the current frame
                processed = draw_cached_overlays(frame)
                fast_frame_display(stframe, processed)

                play_alert_if_new()
                # Throttle metrics to every 10th frame — reduces Streamlit overhead
                if _display_frame_n % 10 == 0:
                    _render_metrics()
                
                # Maintain original frame rate
                elapsed = time.perf_counter() - t0
                sleep_time = max(0.0, (1.0 / _fps) - elapsed)
                if sleep_time > 0:
                    time.sleep(sleep_time)

            async_pipeline.stop()
            cap.release()
            os.unlink(tmp.name)
            
            # Clear the looping audio tag so it doesn't play forever after the video ends!
            audio_placeholder.empty()
            
            st.success("✅ Video processing completed.")

            # Final safety report (Sprint 5)
            summary = get_logger_summary()
            st.divider()
            st.subheader("📊 Session Safety Report")
            sc1, sc2, sc3 = st.columns(3)
            sc1.metric("False-Safe Events",   summary["false_safe_count"],
                       delta="Target: 0",
                       delta_color="inverse")
            sc2.metric("False-Safe Rate",
                       f"{summary['false_safe_rate']*100:.1f}%")
            sc3.metric("Total State Switches", summary["state_switches"])
            st.caption(f"Event log saved → `{summary['log_path']}`")
    else:
        st.info("👆 Upload a video file to begin analysis.")

# ── Live Camera ───────────────────────────────────────────────────────────────
elif mode == "Live Camera":
    camera_mode = st.radio("Camera Mode:", ["Local (OpenCV)", "Web (Browser)"], horizontal=True)

    if camera_mode == "Local (OpenCV)":
        stframe = st.empty()
        run = st.checkbox("▶ Start Camera")

        if run:
            reset_pipeline()
            cap = cv2.VideoCapture(0)
            if not cap.isOpened():
                st.error("❌ Could not access camera.")
            else:
                # Set camera buffer size to 1 to reduce latency
                cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
                
                # Start background thread for YOLO and safety logic execution
                async_pipeline = AsyncPipeline(_config)
                
                while run and cap.isOpened():
                    t0 = time.perf_counter()
                    
                    # Flush the buffer: grab any queued frames to make sure we retrieve the freshest one
                    for _ in range(4):
                        cap.grab()
                    ret, frame = cap.retrieve()
                    if not ret:
                        ret, frame = cap.read()
                        
                    if not ret:
                        break

                    # Send frame to background safety processing thread
                    async_pipeline.update_frame(frame)

                    # Draw latest processed safety overlays on the current frame
                    processed = draw_cached_overlays(frame)
                    fast_frame_display(stframe, processed)

                    play_alert_if_new()
                    _render_metrics()
                    
                    # Match camera frame rate (30 FPS default)
                    elapsed = time.perf_counter() - t0
                    sleep_time = max(0.0, (1.0 / fps) - elapsed)
                    if sleep_time > 0:
                        time.sleep(sleep_time)

                async_pipeline.stop()
                cap.release()
                st.success("✅ Camera stopped.")

    else:  # Web (Browser) via WebRTC
        st.info("📹 Click START to use browser camera (works on deployed apps)")

        def video_frame_callback(frame):
            img = frame.to_ndarray(format="bgr24")
            processed = process_frame(img, _config)
            return av.VideoFrame.from_ndarray(processed, format="bgr24")

        webrtc_ctx = webrtc_streamer(
            key                    = "pedestrian-safety-web",
            mode                   = WebRtcMode.SENDRECV,
            rtc_configuration      = RTCConfiguration(
                {"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]}
            ),
            video_frame_callback   = video_frame_callback,
            media_stream_constraints = {"video": True, "audio": False},
            async_processing       = True,
        )

        if webrtc_ctx:
            try:
                while webrtc_ctx.state.playing:
                    play_alert_if_new()
                    _render_metrics()
                    time.sleep(0.35)
            except Exception:
                pass
