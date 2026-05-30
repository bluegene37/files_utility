import os
import re

files = [
    ('lib/screens/home_screen.dart', 'FileProcessProvider'),
    ('lib/screens/copy_files_screen.dart', 'CopyFilesProvider'),
    ('lib/screens/delete_screen.dart', 'DeleteProcessProvider'),
]

for filepath, provider_name in files:
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Find the Theme wrapper for ExpansionTile
    # We will search for 'Theme(\n' ... 'child: ExpansionTile('
    start_idx = content.find('Theme(\n                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),\n                            child: ExpansionTile(')
    if start_idx == -1:
        # Try finding 'ExpansionTile' directly and go backwards to 'Theme'
        exp_idx = content.find('child: ExpansionTile(')
        if exp_idx != -1:
            start_idx = content.rfind('Theme(', 0, exp_idx)
            
    if start_idx == -1:
        print(f"ExpansionTile not found in {filepath}")
        continue
        
    # Find the matching closing parenthesis for Theme(
    stack = []
    end_idx = -1
    children_start = -1
    children_end = -1
    for i in range(start_idx, len(content)):
        if content[i] == '(':
            stack.append(i)
        elif content[i] == ')':
            stack.pop()
            if len(stack) == 0:
                end_idx = i
                break
    
    if end_idx == -1:
        print("Could not find end of Theme block")
        continue
        
    theme_block = content[start_idx:end_idx+2] # include '),' if present
    
    # Extract the 'children: [' part
    c_start = theme_block.find('children: [')
    c_end = theme_block.rfind('],')
    if c_start != -1 and c_end != -1:
        children_content = theme_block[c_start + len('children: ['):c_end]
    else:
        print(f"Could not find children array in {filepath}")
        continue
        
    # Replace Theme block with a button
    button_code = f'''Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () => _showAdvancedSettingsDialog(context, provider),
                              icon: const Icon(Icons.settings, size: 16, color: AppColors.accent),
                              label: const Text('Advanced Settings', style: TextStyle(color: AppColors.accent)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.cardBorder),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          )'''
    
    new_content = content[:start_idx] + button_code + content[end_idx+2:]
    
    # Determine color for the modal title based on the screen
    color = "AppColors.accent"
    if "delete" in filepath:
        color = "AppColors.error"
    elif "copy" in filepath:
        color = "AppColors.info"
        
    dialog_code = f'''

  void _showAdvancedSettingsDialog(BuildContext context, {provider_name} provider) {{
    showDialog(
      context: context,
      builder: (dialogContext) {{
        return Consumer<{provider_name}>(
          builder: (context, provider, child) {{
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.settings, size: 22, color: {color}),
                  const SizedBox(width: 8),
                  const Text('Advanced Settings', style: TextStyle(fontSize: 18)),
                ],
              ),
              contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.7,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [{children_content}],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Done'),
                ),
              ],
            );
          }},
        );
      }},
    );
  }}
}}'''
    # We need to insert this method right before the last closing brace of the file
    last_brace_idx = new_content.rfind('}')
    new_content = new_content[:last_brace_idx] + dialog_code
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(new_content)
        
    print(f"Successfully refactored {filepath}")
