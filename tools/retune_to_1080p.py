#!/usr/bin/env python3
"""Multiply all sx()/sy() arguments by 1.5 to retune from 720p to 1080p design ref."""
import re
import os
import shutil

FILES = [
    "../constants.lua",
    "../main.lua",
    "../ui.lua",
    "../game.lua",
    "../chart.lua",
    "../controls/slider.lua",
    "../src/ui.lua",
]

def transform_number(m):
    """Given a regex match of sx(NUMBER) or sy(NUMBER), multiply NUMBER by 1.5."""
    full = m.group(0)       # e.g. "sx(165)" or "sy(1.5)"
    func = m.group(1)       # "sx" or "sy"
    num_str = m.group(2)    # "165" or "1.5"
    
    # Parse the number
    if '.' in num_str:
        num = float(num_str)
    else:
        num = int(num_str)
    
    new_num = num * 1.5
    
    # Format nicely: use int if exact, otherwise keep reasonable precision
    if new_num == int(new_num):
        new_num_str = str(int(new_num))
    else:
        # Round to avoid floating point issues (e.g. 247.5 stays 247.5)
        new_num_str = f"{new_num:.4f}".rstrip('0').rstrip('.')
    
    return f"{func}({new_num_str})"

pattern = re.compile(r'(sx|sy)\(([\d]+(?:\.[\d]+)?)\)')

total_replacements = 0

for rel_path in FILES:
    filepath = os.path.join(os.path.dirname(__file__), rel_path)
    if not os.path.exists(filepath):
        print(f"⚠  SKIP (not found): {filepath}")
        continue
    
    with open(filepath, 'r') as f:
        content = f.read()
    
    new_content, count = pattern.subn(transform_number, content)
    total_replacements += count
    
    if count > 0:
        # Backup
        backup = filepath + ".bak"
        shutil.copy2(filepath, backup)
        
        with open(filepath, 'w') as f:
            f.write(new_content)
        print(f"✓ {rel_path}: {count} replacements (backup: .bak)")
    else:
        print(f"  {rel_path}: no changes")

print(f"\nTotal replacements: {total_replacements}")
print("Now update BASE_W, BASE_H in constants.lua manually.")
