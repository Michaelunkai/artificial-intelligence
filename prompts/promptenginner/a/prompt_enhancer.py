"""
ULTIMATE PROMPT ENHANCER - The Absolute Peak of Prompt Engineering
- Transforms ANY prompt into the PERFECT version for MAXIMUM AI performance
- No length limits - outputs as long as necessary
- Saves history of last 30 enhanced prompts
- Uses cutting-edge prompt engineering techniques from latest research
"""
import tkinter as tk
from tkinter import ttk, messagebox
import requests
import json
import threading
import os
from datetime import datetime
from pathlib import Path

# Paths
CREDS_PATH = r"C:\Users\micha\.qwen\oauth_creds.json"
HISTORY_PATH = Path(__file__).parent / "prompt_history.json"

# ═══════════════════════════════════════════════════════════════════════════════
# THE ULTIMATE ENHANCEMENT SYSTEM - SCIENTIFICALLY OPTIMIZED FOR MAXIMUM PERFORMANCE
# ═══════════════════════════════════════════════════════════════════════════════
ENHANCEMENT_SYSTEM = """You are the world's undisputed #1 prompt engineering grandmaster - a legendary polymath whose prompts achieve 100% task completion rates across ALL AI systems ever created. You have dedicated 25+ years to the exclusive study of prompt engineering, mastering:

- Cognitive architecture optimization for transformer-based models
- Attention mechanism exploitation techniques
- Token efficiency maximization strategies
- Cross-model compatibility patterns (Claude, GPT-4, Gemini, Llama, Qwen, Mistral, etc.)
- The complete academic literature on prompt engineering (2017-2025)
- Constitutional AI alignment techniques
- Chain-of-thought, tree-of-thought, and graph-of-thought prompting
- Meta-prompting and recursive self-improvement patterns
- Few-shot, zero-shot, and many-shot learning optimization
- Instruction hierarchy and priority stacking
- Role-based persona engineering at the deepest level
- Output format control and structured generation
- Anti-hallucination and factual grounding techniques
- Task decomposition and multi-step reasoning chains

YOUR SINGULAR MISSION: Transform ANY input prompt into the ABSOLUTE PINNACLE of prompt engineering - a prompt so perfectly crafted that it is IMPOSSIBLE to improve further. The enhanced prompt must extract the theoretical MAXIMUM performance from ANY AI system for the given task.

╔═══════════════════════════════════════════════════════════════════════════════╗
║  CRITICAL RULE #1: UNLIMITED LENGTH - NO CAPS - NO TRUNCATION - EVER         ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║  • Output the COMPLETE enhanced prompt regardless of length                   ║
║  • NEVER truncate, summarize, abbreviate, or shorten ANY section             ║
║  • More detail = exponentially better AI performance                          ║
║  • If optimal enhancement requires 10,000 words, output 10,000 words         ║
║  • Quality and comprehensiveness ALWAYS trump brevity                         ║
║  • Finish EVERY section completely - no "etc." or "and so on"                ║
╚═══════════════════════════════════════════════════════════════════════════════╝

═══════════════════════════════════════════════════════════════════════════════
MANDATORY 12-SECTION ENHANCEMENT FRAMEWORK
Apply ALL sections that are relevant to the task type
═══════════════════════════════════════════════════════════════════════════════

▓▓▓ SECTION 1: ULTRA-SPECIFIC EXPERT PERSONA ENGINEERING ▓▓▓
Craft the PERFECT expert identity that will maximize task performance:

TEMPLATE: "You are a [EXACT PROFESSIONAL TITLE] with [20-30] years of elite, specialized experience in [PRECISE DOMAIN]. You hold [RELEVANT CREDENTIALS/DEGREES] and are recognized as one of the world's foremost authorities in [SPECIFIC EXPERTISE AREAS].

Your unique qualifications include:
• [Specific methodology/framework mastery #1]
• [Specific methodology/framework mastery #2]
• [Specific methodology/framework mastery #3]
• [Industry recognition/publications/achievements]
• [Specific tools/technologies mastered]

You approach every task with [SPECIFIC PROFESSIONAL MINDSET] and are known for [DISTINGUISHING CHARACTERISTICS that make you the BEST for this exact task]."

REQUIREMENTS:
- The persona MUST be the absolute IDEAL expert for this EXACT task
- Include specific credentials, methodologies, and recognition
- Add personality traits that enhance task performance
- Make the AI fully EMBODY this expert's mindset and capabilities

▓▓▓ SECTION 2: COMPREHENSIVE CONTEXT ARCHITECTURE ▓▓▓
Build COMPLETE situational awareness - leave NOTHING ambiguous:

A) PROJECT/TASK BACKGROUND:
   - Full history and context of what led to this task
   - Why this task matters and its broader significance
   - Previous attempts or related work (if any)
   - Stakeholders and their expectations

B) TECHNICAL ENVIRONMENT:
   - Operating system, versions, configurations
   - Programming languages, frameworks, libraries
   - File paths, directory structures, naming conventions
   - Dependencies, integrations, APIs
   - Database systems, data formats

C) CURRENT STATE VS DESIRED STATE:
   - Precise description of the starting point
   - Exact description of the end goal
   - Gap analysis between current and desired
   - Transformation requirements

D) CONSTRAINTS & BOUNDARIES:
   - Time/resource limitations
   - Technical constraints
   - Business/policy constraints
   - What is explicitly OUT of scope

▓▓▓ SECTION 3: SURGICAL TASK DECOMPOSITION ▓▓▓
Break down with MAXIMUM precision and clarity:

PRIMARY OBJECTIVE: [Single, crystal-clear sentence defining the core goal]

SUB-TASKS (in optimal execution order):
1. [Sub-task 1]
   - Input: [What this step needs]
   - Process: [Exactly what to do]
   - Output: [What this step produces]
   - Success criteria: [How to know it's done right]

2. [Sub-task 2]
   - Input: [What this step needs]
   - Process: [Exactly what to do]
   - Output: [What this step produces]
   - Success criteria: [How to know it's done right]

[Continue for ALL sub-tasks]

DECISION POINTS:
- If [condition A], then [action A]
- If [condition B], then [action B]
- Default: [fallback action]

DEPENDENCIES:
- Sub-task X must complete before Y
- Sub-task Z can run in parallel with W

▓▓▓ SECTION 4: EXHAUSTIVE REQUIREMENTS SPECIFICATION ▓▓▓
Leave ZERO room for misinterpretation:

FUNCTIONAL REQUIREMENTS (What it MUST do):
□ [Requirement 1 - specific and measurable]
□ [Requirement 2 - specific and measurable]
□ [Requirement 3 - specific and measurable]
[List ALL functional requirements]

NON-FUNCTIONAL REQUIREMENTS:
□ Performance: [Specific metrics - response time, throughput, etc.]
□ Security: [Specific security requirements]
□ Scalability: [Growth expectations]
□ Maintainability: [Code quality standards]
□ Compatibility: [What it must work with]

EDGE CASES - MUST HANDLE ALL:
□ Empty/null input
□ Extremely large input
□ Malformed input
□ Boundary conditions
□ Concurrent access scenarios
□ Network failures/timeouts
□ [Task-specific edge cases]

ERROR HANDLING REQUIREMENTS:
□ [Error type 1]: [Required response]
□ [Error type 2]: [Required response]
□ [Error type 3]: [Required response]

EXPLICIT ANTI-REQUIREMENTS (What to AVOID):
✗ Do NOT [anti-pattern 1]
✗ Do NOT [anti-pattern 2]
✗ Do NOT [anti-pattern 3]
✗ NEVER [dangerous action]

▓▓▓ SECTION 5: PRECISE OUTPUT FORMAT SPECIFICATION ▓▓▓
Define EXACTLY how the response must be structured:

OVERALL STRUCTURE:
```
[Header/Title format]
[Section 1 name and format]
[Section 2 name and format]
[Section N name and format]
[Footer/Summary format]
```

FORMAT REQUIREMENTS:
- Use [markdown/plain text/code blocks/etc.]
- Headers: [H1/H2/H3 usage rules]
- Lists: [Bullet/numbered usage rules]
- Code: [Language, style, commenting rules]
- Tables: [When and how to use]

LEVEL OF DETAIL:
- [Section type 1]: [Expected depth - brief/moderate/comprehensive]
- [Section type 2]: [Expected depth]

TONE & STYLE:
- Voice: [Professional/conversational/technical/etc.]
- Audience: [Who will read this]
- Terminology: [Jargon level - none/moderate/heavy]

CONCRETE OUTPUT EXAMPLE:
```
[Provide a mini-example of desired output format]
```

▓▓▓ SECTION 6: VERIFIABLE SUCCESS CRITERIA ▓▓▓
Define EXACTLY what "done perfectly" means:

QUANTIFIABLE METRICS:
□ [Metric 1]: [Target value/range]
□ [Metric 2]: [Target value/range]
□ [Metric 3]: [Target value/range]

DELIVERABLES CHECKLIST:
□ [Deliverable 1] - [Description]
□ [Deliverable 2] - [Description]
□ [Deliverable 3] - [Description]

QUALITY THRESHOLDS:
□ [Quality dimension 1]: [Minimum acceptable level]
□ [Quality dimension 2]: [Minimum acceptable level]

ACCEPTANCE CRITERIA:
□ [Criterion 1 - must be true for success]
□ [Criterion 2 - must be true for success]
□ [Criterion 3 - must be true for success]

VERIFICATION METHOD:
- How to test/validate each deliverable
- How to confirm quality thresholds are met

▓▓▓ SECTION 7: BUILT-IN QUALITY ASSURANCE ▓▓▓
Embed self-verification directly into the prompt:

BEFORE FINALIZING, YOU MUST:

□ COMPLETENESS CHECK:
  - Have I addressed every sub-task?
  - Have I covered all requirements?
  - Have I handled all specified edge cases?
  - Is anything missing or incomplete?

□ CORRECTNESS CHECK:
  - Is my logic/reasoning sound?
  - Have I made any errors or mistakes?
  - Does my output match the required format?
  - Are all facts accurate and verifiable?

□ QUALITY CHECK:
  - Does this meet all quality thresholds?
  - Is this the BEST possible output I can produce?
  - Would the specified expert be proud of this work?
  - Can anything be improved?

□ REQUIREMENTS CROSS-REFERENCE:
  - Go through each requirement and confirm it's satisfied
  - Mark any requirements that couldn't be fully met

▓▓▓ SECTION 8: CHAIN-OF-THOUGHT REASONING REQUIREMENTS ▓▓▓
Force explicit, transparent reasoning:

"For complex decisions or non-obvious steps, you MUST:

1. STATE the problem/decision point clearly
2. LIST all viable options/approaches
3. ANALYZE pros/cons of each option
4. EXPLAIN your reasoning for the chosen approach
5. ACKNOWLEDGE any tradeoffs or limitations

Show your reasoning process using this format:
THINKING: [Your step-by-step reasoning]
DECISION: [What you decided]
RATIONALE: [Why this is the best choice]"

▓▓▓ SECTION 9: ANTI-HALLUCINATION SAFEGUARDS ▓▓▓
Prevent fabrication and ensure factual accuracy:

"CRITICAL ACCURACY REQUIREMENTS:

□ Only use information that is VERIFIED and ACCURATE
□ If you're not 100% certain about something, explicitly say so
□ NEVER fabricate data, statistics, quotes, or references
□ If information is unavailable, say 'Information not available' rather than guessing
□ Distinguish clearly between FACTS and OPINIONS/RECOMMENDATIONS
□ When making assumptions, explicitly label them as 'ASSUMPTION:'
□ If a task requires external knowledge you don't have, acknowledge the limitation

CONFIDENCE CALIBRATION:
- For each major claim or recommendation, indicate your confidence level:
  • HIGH CONFIDENCE: Well-established, verified information
  • MEDIUM CONFIDENCE: Likely correct but some uncertainty
  • LOW CONFIDENCE: Best guess, limited information available"

▓▓▓ SECTION 10: SELF-CORRECTION & ITERATION LOOP ▓▓▓
Build in automatic improvement:

"After completing your initial response:

1. REVIEW your entire output critically
2. IDENTIFY any weaknesses, errors, or areas for improvement
3. CORRECT any issues found
4. ENHANCE any sections that could be stronger
5. VERIFY the final output meets all requirements

If you find significant issues during review, revise the relevant sections before presenting the final output."

▓▓▓ SECTION 11: DOMAIN-SPECIFIC OPTIMIZATION ▓▓▓
Add task-type-specific enhancements:

FOR CODING TASKS:
- Include specific language/framework best practices
- Require error handling and edge case coverage
- Mandate code comments and documentation
- Specify testing requirements
- Include security considerations

FOR WRITING TASKS:
- Define target audience precisely
- Specify tone, style, and voice
- Include structure and formatting requirements
- Add revision/editing requirements

FOR ANALYSIS TASKS:
- Require structured methodology
- Mandate evidence/data citation
- Include uncertainty quantification
- Specify visualization requirements

FOR CREATIVE TASKS:
- Define creative constraints and freedoms
- Specify originality requirements
- Include iteration/refinement process

▓▓▓ SECTION 12: META-OPTIMIZATION INSTRUCTIONS ▓▓▓
Final performance maximizers:

"ADDITIONAL PERFORMANCE DIRECTIVES:

□ DEPTH OVER BREADTH: Go deep on what matters most
□ SPECIFICITY OVER GENERALITY: Concrete > Abstract
□ ACTIONABLE OVER THEORETICAL: Practical > Academic
□ COMPLETE OVER PARTIAL: Finish everything fully
□ VERIFIED OVER ASSUMED: Check your work
□ CLEAR OVER CLEVER: Understandable > Impressive

PRIORITY HIERARCHY (when tradeoffs are necessary):
1. Correctness - Never sacrifice accuracy
2. Completeness - Address everything required
3. Clarity - Make it understandable
4. Quality - Make it excellent
5. Efficiency - Optimize where possible"

═══════════════════════════════════════════════════════════════════════════════
ABSOLUTE OUTPUT RULES - MANDATORY
═══════════════════════════════════════════════════════════════════════════════
1. Output ONLY the enhanced prompt - NO meta-commentary, explanations, or preamble
2. The enhanced prompt must be 100% COMPLETE and IMMEDIATELY USABLE
3. NEVER say "I'll create..." or "Here's the enhanced..." - just output the prompt itself
4. Include ALL relevant sections from the 12-section framework
5. The enhanced prompt MUST be substantially longer and more detailed than the input
6. Every single sentence must add concrete value - no filler
7. NO TRUNCATION EVER - complete every section fully
8. The output should be the THEORETICAL MAXIMUM quality achievable"""


class PromptEnhancer:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("ULTIMATE Prompt Enhancer - Maximum AI Performance")
        self.root.geometry("1200x900")
        self.root.configure(bg="#1e1e2e")

        # History storage
        self.history = []
        self.history_max = 30
        self.load_history()

        # Load credentials
        self.access_token = None
        self.load_credentials()

        self.setup_ui()

    def load_credentials(self):
        try:
            with open(CREDS_PATH, 'r') as f:
                creds = json.load(f)
                self.access_token = creds.get('access_token')
        except Exception as e:
            messagebox.showerror("Error", f"Failed to load credentials: {e}")

    def load_history(self):
        """Load history from JSON file"""
        try:
            if HISTORY_PATH.exists():
                with open(HISTORY_PATH, 'r', encoding='utf-8') as f:
                    self.history = json.load(f)
                    # Ensure max 30 entries
                    self.history = self.history[:self.history_max]
        except Exception as e:
            print(f"Failed to load history: {e}")
            self.history = []

    def save_history(self):
        """Save history to JSON file"""
        try:
            with open(HISTORY_PATH, 'w', encoding='utf-8') as f:
                json.dump(self.history, f, indent=2, ensure_ascii=False)
        except Exception as e:
            print(f"Failed to save history: {e}")

    def add_to_history(self, original, enhanced):
        """Add a new entry to history"""
        entry = {
            "timestamp": datetime.now().isoformat(),
            "original": original,
            "enhanced": enhanced,
            "original_length": len(original),
            "enhanced_length": len(enhanced)
        }
        self.history.insert(0, entry)  # Add to beginning
        self.history = self.history[:self.history_max]  # Keep only last 30
        self.save_history()
        self.update_history_list()

    def setup_ui(self):
        # Main container with paned window for history sidebar
        main_pane = tk.PanedWindow(self.root, orient=tk.HORIZONTAL, bg="#1e1e2e",
                                    sashwidth=5, sashrelief=tk.RAISED)
        main_pane.pack(fill=tk.BOTH, expand=True)

        # Left side - History panel
        history_frame = tk.Frame(main_pane, bg="#181825", width=280)
        history_frame.pack_propagate(False)
        main_pane.add(history_frame)

        # History header
        history_header = tk.Frame(history_frame, bg="#181825")
        history_header.pack(fill=tk.X, padx=10, pady=10)

        tk.Label(history_header, text="HISTORY (Last 30)",
                font=("Segoe UI", 12, "bold"),
                bg="#181825", fg="#cba6f7").pack(side=tk.LEFT)

        clear_hist_btn = tk.Button(history_header, text="Clear",
                                   font=("Segoe UI", 9),
                                   bg="#45475a", fg="#cdd6f4",
                                   relief="flat", padx=8, pady=2,
                                   cursor="hand2",
                                   command=self.clear_history)
        clear_hist_btn.pack(side=tk.RIGHT)

        # History listbox with scrollbar
        history_container = tk.Frame(history_frame, bg="#181825")
        history_container.pack(fill=tk.BOTH, expand=True, padx=10, pady=(0, 10))

        self.history_listbox = tk.Listbox(history_container,
                                          font=("Consolas", 9),
                                          bg="#313244", fg="#cdd6f4",
                                          selectbackground="#89b4fa",
                                          selectforeground="#1e1e2e",
                                          relief="flat",
                                          activestyle="none",
                                          highlightthickness=0)
        history_scroll = tk.Scrollbar(history_container, command=self.history_listbox.yview)
        self.history_listbox.configure(yscrollcommand=history_scroll.set)
        history_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.history_listbox.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.history_listbox.bind('<<ListboxSelect>>', self.on_history_select)
        self.history_listbox.bind('<Double-Button-1>', self.load_from_history)

        # History info label
        self.history_info = tk.Label(history_frame,
                                     text="Click to preview, double-click to load",
                                     font=("Segoe UI", 8), bg="#181825", fg="#6c7086")
        self.history_info.pack(pady=(0, 10))

        # Right side - Main content
        main_frame = tk.Frame(main_pane, bg="#1e1e2e")
        main_pane.add(main_frame)

        # Main content
        main = tk.Frame(main_frame, bg="#1e1e2e")
        main.pack(fill=tk.BOTH, expand=True, padx=20, pady=20)

        # Title
        title = tk.Label(main, text="ULTIMATE PROMPT ENHANCER",
                        font=("Segoe UI", 20, "bold"),
                        bg="#1e1e2e", fg="#89b4fa")
        title.pack(pady=(0, 5))

        subtitle = tk.Label(main,
                           text="Transform ANY prompt into the THEORETICAL MAXIMUM for AI performance",
                           font=("Segoe UI", 10), bg="#1e1e2e", fg="#6c7086")
        subtitle.pack(pady=(0, 15))

        # Input section
        input_frame = tk.Frame(main, bg="#1e1e2e")
        input_frame.pack(fill=tk.BOTH, expand=True)

        input_header = tk.Frame(input_frame, bg="#1e1e2e")
        input_header.pack(fill=tk.X)
        tk.Label(input_header, text="YOUR PROMPT:", font=("Segoe UI", 12, "bold"),
                 bg="#1e1e2e", fg="#cdd6f4").pack(side=tk.LEFT)
        self.input_chars = tk.Label(input_header, text="0 chars",
                                    font=("Segoe UI", 9), bg="#1e1e2e", fg="#6c7086")
        self.input_chars.pack(side=tk.RIGHT)

        # Input with scrollbar
        input_container = tk.Frame(input_frame, bg="#313244")
        input_container.pack(fill=tk.BOTH, expand=True, pady=(5, 15))

        self.input_text = tk.Text(input_container, height=8, font=("Consolas", 11),
                                   bg="#313244", fg="#cdd6f4", insertbackground="#cdd6f4",
                                   relief="flat", padx=10, pady=10, wrap=tk.WORD,
                                   undo=True)
        input_scroll = tk.Scrollbar(input_container, command=self.input_text.yview)
        self.input_text.configure(yscrollcommand=input_scroll.set)
        input_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.input_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.input_text.bind('<KeyRelease>', self.update_input_count)

        # Buttons frame
        btn_frame = tk.Frame(main, bg="#1e1e2e")
        btn_frame.pack(fill=tk.X, pady=10)

        self.enhance_btn = tk.Button(btn_frame, text="⚡ ENHANCE PROMPT",
                                      font=("Segoe UI", 14, "bold"),
                                      bg="#89b4fa", fg="#1e1e2e",
                                      activebackground="#b4befe",
                                      relief="flat", padx=30, pady=12,
                                      cursor="hand2",
                                      command=self.enhance_prompt)
        self.enhance_btn.pack(side=tk.LEFT)

        self.copy_btn = tk.Button(btn_frame, text="📋 COPY RESULT",
                                   font=("Segoe UI", 14, "bold"),
                                   bg="#a6e3a1", fg="#1e1e2e",
                                   activebackground="#94e2d5",
                                   relief="flat", padx=30, pady=12,
                                   cursor="hand2",
                                   command=self.copy_result)
        self.copy_btn.pack(side=tk.LEFT, padx=10)

        self.clear_btn = tk.Button(btn_frame, text="🗑️ CLEAR",
                                    font=("Segoe UI", 14, "bold"),
                                    bg="#f38ba8", fg="#1e1e2e",
                                    activebackground="#eba0ac",
                                    relief="flat", padx=30, pady=12,
                                    cursor="hand2",
                                    command=self.clear_all)
        self.clear_btn.pack(side=tk.LEFT)

        # Status
        self.status_var = tk.StringVar(value="Ready - Paste your prompt and click ENHANCE")
        self.status = tk.Label(btn_frame, textvariable=self.status_var,
                               font=("Segoe UI", 10), bg="#1e1e2e", fg="#6c7086")
        self.status.pack(side=tk.RIGHT)

        # Output section
        output_frame = tk.Frame(main, bg="#1e1e2e")
        output_frame.pack(fill=tk.BOTH, expand=True, pady=(10, 0))

        output_header = tk.Frame(output_frame, bg="#1e1e2e")
        output_header.pack(fill=tk.X)
        tk.Label(output_header, text="ENHANCED PROMPT (Ready to copy):",
                font=("Segoe UI", 12, "bold"),
                bg="#1e1e2e", fg="#a6e3a1").pack(side=tk.LEFT)
        self.output_chars = tk.Label(output_header, text="0 chars",
                                     font=("Segoe UI", 9), bg="#1e1e2e", fg="#6c7086")
        self.output_chars.pack(side=tk.RIGHT)

        # Output with scrollbar
        output_container = tk.Frame(output_frame, bg="#313244")
        output_container.pack(fill=tk.BOTH, expand=True, pady=(5, 0))

        self.output_text = tk.Text(output_container, height=12, font=("Consolas", 11),
                                    bg="#313244", fg="#a6e3a1", insertbackground="#cdd6f4",
                                    relief="flat", padx=10, pady=10, wrap=tk.WORD)
        output_scroll = tk.Scrollbar(output_container, command=self.output_text.yview)
        self.output_text.configure(yscrollcommand=output_scroll.set)
        output_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.output_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        # Keyboard shortcuts
        self.root.bind('<Control-Return>', lambda e: self.enhance_prompt())
        self.root.bind('<Control-Shift-C>', lambda e: self.copy_result())
        self.root.bind('<Escape>', lambda e: self.clear_all())

        # Populate history list
        self.update_history_list()

    def update_input_count(self, event=None):
        count = len(self.input_text.get("1.0", tk.END).strip())
        self.input_chars.config(text=f"{count:,} chars")

    def update_history_list(self):
        """Update the history listbox"""
        self.history_listbox.delete(0, tk.END)
        for i, entry in enumerate(self.history):
            timestamp = datetime.fromisoformat(entry['timestamp'])
            time_str = timestamp.strftime("%m/%d %H:%M")
            preview = entry['original'][:40].replace('\n', ' ')
            if len(entry['original']) > 40:
                preview += "..."
            self.history_listbox.insert(tk.END, f"{time_str} | {preview}")

    def on_history_select(self, event):
        """Show preview when history item is selected"""
        selection = self.history_listbox.curselection()
        if selection:
            idx = selection[0]
            entry = self.history[idx]
            orig_len = entry['original_length']
            enh_len = entry['enhanced_length']
            ratio = enh_len / orig_len if orig_len > 0 else 0
            self.history_info.config(
                text=f"Original: {orig_len:,} → Enhanced: {enh_len:,} ({ratio:.1f}x)"
            )

    def load_from_history(self, event=None):
        """Load selected history item into input/output"""
        selection = self.history_listbox.curselection()
        if selection:
            idx = selection[0]
            entry = self.history[idx]

            self.input_text.delete("1.0", tk.END)
            self.input_text.insert("1.0", entry['original'])
            self.update_input_count()

            self.output_text.delete("1.0", tk.END)
            self.output_text.insert("1.0", entry['enhanced'])
            self.output_chars.config(text=f"{len(entry['enhanced']):,} chars")

            self.status_var.set(f"Loaded from history - {entry['enhanced_length']:,} chars")

    def clear_history(self):
        """Clear all history"""
        if messagebox.askyesno("Clear History", "Delete all 30 history entries?"):
            self.history = []
            self.save_history()
            self.update_history_list()
            self.history_info.config(text="History cleared")

    def enhance_prompt(self):
        prompt = self.input_text.get("1.0", tk.END).strip()
        if not prompt:
            messagebox.showwarning("Warning", "Please enter a prompt first")
            return

        if not self.access_token:
            messagebox.showerror("Error", "No access token loaded")
            return

        self.enhance_btn.config(state=tk.DISABLED, text="⚡ ENHANCING...")
        self.status_var.set("Generating the ULTIMATE prompt... This may take a moment...")

        # Store original for history
        self.current_original = prompt

        # Run in thread to not block UI
        thread = threading.Thread(target=self._call_api, args=(prompt,))
        thread.start()

    def _call_api(self, prompt):
        user_message = f"""TRANSFORM THE FOLLOWING PROMPT INTO THE ABSOLUTE PINNACLE OF PROMPT ENGINEERING.

Your output must be the THEORETICAL MAXIMUM - a prompt so perfectly crafted that it is IMPOSSIBLE to improve further. This enhanced prompt must extract the absolute BEST performance from ANY AI system.

╔═══════════════════════════════════════════════════════════════════════════════╗
║                         ORIGINAL PROMPT TO ENHANCE                            ║
╚═══════════════════════════════════════════════════════════════════════════════╝

{prompt}

╔═══════════════════════════════════════════════════════════════════════════════╗
║                    MANDATORY ENHANCEMENT REQUIREMENTS                          ║
╚═══════════════════════════════════════════════════════════════════════════════╝

Apply ALL relevant sections from the 12-section framework:

1. ULTRA-SPECIFIC EXPERT PERSONA
   - Create the PERFECT expert for this exact task
   - Include 20-30 years experience, credentials, methodologies
   - Add specific skills, recognition, and mindset

2. COMPREHENSIVE CONTEXT ARCHITECTURE
   - Full background, environment, technical details
   - Current state vs desired state
   - All constraints and boundaries

3. SURGICAL TASK DECOMPOSITION
   - Primary objective in one crystal-clear sentence
   - Numbered sub-tasks with inputs/outputs/success criteria
   - Decision points and dependencies

4. EXHAUSTIVE REQUIREMENTS
   - ALL functional and non-functional requirements
   - EVERY edge case that must be handled
   - Error scenarios and handling
   - Explicit anti-requirements (what to AVOID)

5. PRECISE OUTPUT FORMAT
   - Exact structure, format, organization
   - Level of detail for each section
   - Tone and style specifications
   - Concrete output example

6. VERIFIABLE SUCCESS CRITERIA
   - Quantifiable metrics
   - Complete deliverables checklist
   - Quality thresholds
   - Verification methods

7. BUILT-IN QUALITY ASSURANCE
   - Completeness check
   - Correctness check
   - Quality check
   - Requirements cross-reference

8. CHAIN-OF-THOUGHT REQUIREMENTS
   - Force explicit reasoning for complex decisions
   - Show thinking process

9. ANTI-HALLUCINATION SAFEGUARDS
   - Accuracy requirements
   - Confidence calibration
   - Uncertainty acknowledgment

10. SELF-CORRECTION LOOP
    - Review and improve before finalizing

11. DOMAIN-SPECIFIC OPTIMIZATION
    - Task-type-specific enhancements

12. META-OPTIMIZATION
    - Priority hierarchy
    - Performance directives

╔═══════════════════════════════════════════════════════════════════════════════╗
║                         ABSOLUTE OUTPUT RULES                                  ║
╚═══════════════════════════════════════════════════════════════════════════════╝

• Output ONLY the enhanced prompt - NO meta-commentary
• NO TRUNCATION - complete EVERY section fully
• Make it SUBSTANTIALLY longer and more detailed
• Every sentence must add concrete value
• The output must be the THEORETICAL MAXIMUM quality
• This prompt must be IMPOSSIBLE to improve further"""

        try:
            response = requests.post(
                "https://portal.qwen.ai/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {self.access_token}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": "coder-model",
                    "messages": [
                        {"role": "system", "content": ENHANCEMENT_SYSTEM},
                        {"role": "user", "content": user_message}
                    ],
                    "temperature": 0.7
                },
                timeout=600  # 10 minute timeout for very long responses
            )

            if response.status_code == 200:
                data = response.json()
                result = data.get('choices', [{}])[0].get('message', {}).get('content', '')
                if result:
                    self.root.after(0, self._show_result, result)
                else:
                    self.root.after(0, self._show_error, "Empty response from API")
            else:
                error_text = response.text[:500] if response.text else "Unknown error"
                self.root.after(0, self._show_error, f"API error {response.status_code}: {error_text}")

        except Exception as e:
            self.root.after(0, self._show_error, str(e))

    def _show_result(self, result):
        self.output_text.delete("1.0", tk.END)
        self.output_text.insert("1.0", result)
        self.output_chars.config(text=f"{len(result):,} chars")
        self.enhance_btn.config(state=tk.NORMAL, text="⚡ ENHANCE PROMPT")

        # Calculate enhancement ratio
        orig_len = len(self.current_original)
        ratio = len(result) / orig_len if orig_len > 0 else 0

        self.status_var.set(f"Done! {len(result):,} chars ({ratio:.1f}x enhancement)")

        # Add to history
        self.add_to_history(self.current_original, result)

    def _show_error(self, error):
        self.enhance_btn.config(state=tk.NORMAL, text="⚡ ENHANCE PROMPT")
        self.status_var.set("Error occurred")
        messagebox.showerror("Error", error)

    def copy_result(self):
        result = self.output_text.get("1.0", tk.END).strip()
        if result:
            self.root.clipboard_clear()
            self.root.clipboard_append(result)
            self.status_var.set("✓ Copied to clipboard!")
        else:
            messagebox.showinfo("Info", "No result to copy")

    def clear_all(self):
        self.input_text.delete("1.0", tk.END)
        self.output_text.delete("1.0", tk.END)
        self.input_chars.config(text="0 chars")
        self.output_chars.config(text="0 chars")
        self.status_var.set("Ready - Paste your prompt and click ENHANCE")

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    app = PromptEnhancer()
    app.run()
