"""The iPad's copy of Project 100K's plan must match the skill's (25.0).

Glance.planTable is a copy of PLAN in project-100k/p100k.py; if one changes and
the other does not, the panel and Arisu's answers disagree about the week."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
swift = (root / "Arisu/Glance.swift").read_text()
skill = (root.parents[1] / "dopamine-control-center/.claude/skills/project-100k/p100k.py").read_text()

table = swift[swift.index("static let planTable"):]
table = table[:table.index("]\n")]
ours = [(p, float(k), float(l)) for p, k, l in re.findall(r'\("([^"]+)", (\d+), (\d+)\)', table)]
plan = skill[skill.index("PLAN = ["):]
plan = plan[:plan.index("]\n")]
theirs = [(p, float(k), float(l)) for _, p, k, l in re.findall(r'\((\d+), "([^"]+)", (\d+), (\d+)\)', plan)]

assert len(ours) == 14 and ours == theirs, (ours, theirs)
print("race plan ok")
