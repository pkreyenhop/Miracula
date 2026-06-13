import re
import os

def classify_action(code):
    code_lower = code.lower()
    
    # Classification rules:
    if any(k in code_lower for k in ["evaluate", "obey", "exit", "fopen", "signals", "printf", "putchar", "stdin", "stdout", "stderr"]):
        return "Runtime Interaction"
    elif any(k in code_lower for k in ["syntax", "acterror"]):
        return "Error Handling"
    elif any(k in code_lower for k in ["nonterminals", "ntmap", "ntspecmap", "predef", "id_who", "gvars", "exports", "freeids", "includees", "embargoes", "exportfiles", "lexdefs", "lexstates"]):
        return "Symbol Table"
    elif any(k in code_lower for k in ["inbnf", "sreds", "lastname", "idsused", "tvarscope", "obrct", "col_fn", "layout", "setlmargin", "unsetlmargin"]):
        return "Parser Bookkeeping"
    else:
        return "AST Construction"

def run():
    with open("parser/rules.y", "r") as f:
        lines = f.readlines()
        
    start_idx = 0
    for idx, line in enumerate(lines):
        if line.strip() == "%%":
            start_idx = idx + 1
            break
            
    current_rule = "unknown"
    actions = []
    
    i = start_idx
    n_lines = len(lines)
    while i < n_lines:
        line = lines[i]
        stripped = line.strip()
        
        # Check rule name
        rule_match = re.match(r"^([a-zA-Z0-9_]+)\s*:", stripped)
        if rule_match:
            current_rule = rule_match.group(1)
            i += 1
            continue
            
        # Parse action block
        if "{" in line and not stripped.startswith("/*") and not stripped.startswith("//"):
            action_lines = []
            brace_count = 0
            start_line_no = i + 1
            
            j = i
            found_block = False
            while j < n_lines:
                curr_line = lines[j]
                action_lines.append(curr_line)
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
            if code.startswith("="):
                code = code[1:].strip()
                
            actions.append({
                "rule": current_rule,
                "line": start_line_no,
                "code": code
            })
        i += 1
        
    # Filter out migrated actions
    filtered_actions = []
    for act in actions:
        code_body = act["code"].strip("{} \n\t")
        if code_body.startswith("$$ = parse_") and ";" in code_body and len(code_body.split(";")) <= 2:
            continue
        if not code_body:
            continue
        filtered_actions.append(act)
        
    # Group actions by classification
    classified = {}
    for act in filtered_actions:
        cls = classify_action(act["code"])
        classified.setdefault(cls, []).append(act)
        
    # Generate markdown content
    md = []
    md.append("# Remaining Parser Semantic Actions Inventory")
    md.append("")
    md.append("This document inventories all remaining inline C actions inside `parser/rules.y` categorized by type. This backlog serves as the migration tracker.")
    md.append("")
    
    # Summary Table
    md.append("## Summary")
    md.append("")
    md.append("| Classification | Count | Description |")
    md.append("|---|---|---|")
    md.append(f"| **AST Construction** | {len(classified.get('AST Construction', []))} | Nodes/cell allocations using `ap`, `cons`, etc. |")
    md.append(f"| **Symbol Table** | {len(classified.get('Symbol Table', []))} | Predefinitions, environment updates, export lists. |")
    md.append(f"| **Runtime Interaction** | {len(classified.get('Runtime Interaction', []))} | Program evaluation (`evaluate`), standard IO redirection. |")
    md.append(f"| **Error Handling** | {len(classified.get('Error Handling', []))} | Syntax error reports and recovery states. |")
    md.append(f"| **Parser Bookkeeping** | {len(classified.get('Parser Bookkeeping', []))} | Token formatting, indentation tracking, BNF states. |")
    md.append("")
    
    # Detail Section
    for cls in ["AST Construction", "Symbol Table", "Runtime Interaction", "Error Handling", "Parser Bookkeeping"]:
        md.append(f"## {cls}")
        md.append("")
        acts = classified.get(cls, [])
        if not acts:
            md.append("*No remaining actions in this category.*")
            md.append("")
            continue
            
        for act in acts:
            md.append(f"### Line {act['line']} (Rule: `{act['rule']}`)")
            md.append("```c")
            md.append(act["code"])
            md.append("```")
            md.append("")
            
    # Write to artifacts directory
    artifact_dir = "/Users/pkreyenhop/.gemini/antigravity-cli/brain/20263bf4-38b4-421e-893b-fb238fc1916e"
    os.makedirs(artifact_dir, exist_ok=True)
    report_path = os.path.join(artifact_dir, "remaining_actions.md")
    
    with open(report_path, "w") as f:
        f.write("\n".join(md))
        
    print(f"Report successfully written to: {report_path}")

if __name__ == "__main__":
    run()
