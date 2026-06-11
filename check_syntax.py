import ast

files = [
    'motion_estimator.py',
    'ego_motion.py',
    'depth_estimator.py',
    'velocity_tracker_2.py',
    'crossing_advisor.py',
    'voice_feedback_2.py',
    'overlay_utils_1.py',
    'test_speed_estimation.py',
]

all_ok = True
for f in files:
    try:
        with open(f, encoding='utf-8') as fh:
            ast.parse(fh.read())
        print(f'  OK  {f}')
    except SyntaxError as e:
        print(f'  ERR {f}: {e}')
        all_ok = False
    except Exception as e:
        print(f'  ERR {f}: {e}')
        all_ok = False

print()
print('All syntax OK' if all_ok else 'SYNTAX ERRORS FOUND')
