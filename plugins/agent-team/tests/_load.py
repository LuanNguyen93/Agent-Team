"""Load a Python script from the agent-team plugin directory."""

import importlib.util
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(rel_folder, name):
    path = os.path.join(ROOT, rel_folder, name + ".py")
    spec = importlib.util.spec_from_file_location("agent_team_" + name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod
