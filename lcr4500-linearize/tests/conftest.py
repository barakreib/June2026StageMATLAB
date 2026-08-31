import sys
import types
from pathlib import Path

# The toolkit dir (parent of tests/) must be importable, and `import hid`
# must succeed without hidapi installed: resolve_device() is pure and never
# touches the module, so a stub keeps these tests hermetic on any machine.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.modules.setdefault("hid", types.ModuleType("hid"))
