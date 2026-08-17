#!/usr/bin/env python3
import importlib.util
from importlib.machinery import SourceFileLoader


loader = SourceFileLoader("nature_largest_live", "/root/.local/bin/llama-agent")
spec = importlib.util.spec_from_loader(loader.name, loader)
nature = importlib.util.module_from_spec(spec)
loader.exec_module(nature)

nature.run_user_input("!win-tools files F 10", [])
