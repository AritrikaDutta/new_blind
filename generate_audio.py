"""Generate pre-recorded voice prompts for pedestrian crossing guidance."""
from gtts import gTTS
import os

AUDIO_DIR = os.path.join(os.path.dirname(__file__), "voice_cache")
os.makedirs(AUDIO_DIR, exist_ok=True)

PROMPTS = {
    "walk_normal":  "It's safe. Cross now and walk at normal pace.",
    "walk_fast":    "Vehicle approaching. Cross now and walk fast.",
    "signal_hand_left":  "Vehicle approaching from left. Raise your left hand to signal, and cross quickly.",
    "signal_hand_right": "Vehicle approaching from right. Raise your right hand to signal, and cross quickly.",
    "stop":         "Stop. Do not cross. Vehicle very close.",
}

for name, text in PROMPTS.items():
    path = os.path.join(AUDIO_DIR, f"{name}.mp3")
    if os.path.exists(path):
        print(f"  [skip] {path} already exists")
        continue
    print(f"  [gen]  {name}.mp3  →  \"{text}\"")
    tts = gTTS(text=text, lang="en", slow=False)
    tts.save(path)

print("Done – all audio files ready in", AUDIO_DIR)
