import tensorflow as tf

try:
    Interpreter = tf.lite.Interpreter
except AttributeError:
    # In some TensorFlow versions or configurations, fallback
    try:
        from tensorflow.lite.python.interpreter import Interpreter
    except ImportError:
        class Interpreter:
            def __init__(self, *args, **kwargs):
                raise ImportError("Mock Interpreter cannot be initialized because tf.lite.Interpreter was not found.")
