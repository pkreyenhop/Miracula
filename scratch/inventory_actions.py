import re

def inventory():
    with open("parser/rules.y", "r") as f:
        lines = f.readlines()
    
    # Find the starting line of the grammar rules (after the first %%)
    start_idx = 0
    for idx, line in enumerate(lines):
        if line.strip() == "%%":
            start_idx = idx + 1
            break
            
    current_rule = "unknown"
    actions = []
    
    # We want to match rule headers like:
    # name:
    # and match action blocks:
    # = { ... } or { ... }
    
    # A simple stateful parser:
    i = start_idx
    n_lines = len(lines)
    while i < n_lines:
        line = lines[i]
        stripped = line.strip()
        
        # Check if we are defining a new rule name
        rule_match = re.match(r"^([a-zA-Z0-9_]+)\s*:", stripped)
        if rule_match:
            current_rule = rule_match.group(1)
            i += 1
            continue
            
        # Look for action blocks
        # Actions in rules.y usually look like:
        # = { code } or just = { or {
        if "{" in line and not stripped.startswith("/*") and not stripped.startswith("//"):
            # Let's extract the full action block by balancing braces
            action_lines = []
            brace_count = 0
            start_line_no = i + 1
            
            j = i
            found_block = False
            while j < n_lines:
                curr_line = lines[j]
                action_lines.append(curr_line)
                
                # Count braces, taking care of comments/strings if possible, or just simple count
                for char in curr_line:
                    if char == "{":
                        brace_count += 1
                        found_block = True
                    elif char == "}":
                        brace_count -= 1
                        
                if found_block and brace_count == 0:
                    i = j
                    break
                j += 1
            
            code = "".join(action_lines).strip()
            # Clean up the leading "=" if present
            if code.startswith("="):
                code = code[1:].strip()
                
            actions.append({
                "rule": current_rule,
                "line": start_line_no,
                "code": code
            })
            
        i += 1
        
    # Print report
    print(f"Total actions found: {len(actions)}")
    for act in actions:
        # Ignore simple single line ones that are already migrated
        # Like { $$ = parse_... }
        code_body = act["code"].strip("{} \n\t")
        if code_body.startswith("$$ = parse_") and ";" in code_body and len(code_body.split(";")) <= 2:
            continue
            
        # Ignore empty or simple assignment
        if not code_body:
            continue
            
        print(f"---")
        print(f"Line {act['line']} in rule '{act['rule']}':")
        print(act["code"])

if __name__ == "__main__":
    inventory()
