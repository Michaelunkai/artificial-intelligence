"""
Prompt Engineer Pro - The Ultimate Prompt Engineering Tool
A comprehensive GUI application for creating, optimizing, and managing AI prompts.
"""

import os
import sys
import json
import threading
import time
import re
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, List, Any, Callable
import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox, filedialog
import webbrowser

# Optional imports with fallbacks
try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False

try:
    import pyperclip
    HAS_PYPERCLIP = True
except ImportError:
    HAS_PYPERCLIP = False


class PromptEngineeringTechniques:
    """Collection of advanced prompt engineering techniques."""

    TECHNIQUES = {
        "chain_of_thought": {
            "name": "Chain of Thought (CoT)",
            "description": "Encourages step-by-step reasoning",
            "template": "Let's approach this step by step:\n\n{prompt}\n\nPlease think through this carefully, showing your reasoning at each step before providing your final answer.",
            "suffix": "\n\nThink step by step."
        },
        "few_shot": {
            "name": "Few-Shot Learning",
            "description": "Provides examples to guide the response",
            "template": "I'll provide some examples to illustrate what I'm looking for:\n\n[Example 1]\nInput: [example input]\nOutput: [example output]\n\n[Example 2]\nInput: [example input]\nOutput: [example output]\n\nNow, please apply the same pattern to:\n{prompt}",
            "suffix": ""
        },
        "role_play": {
            "name": "Role-Based Prompting",
            "description": "Assigns a specific expert role",
            "template": "You are an expert {role} with deep knowledge and years of experience. Using your expertise:\n\n{prompt}",
            "suffix": ""
        },
        "structured_output": {
            "name": "Structured Output",
            "description": "Requests specific format",
            "template": "{prompt}\n\nPlease structure your response as follows:\n1. Summary (2-3 sentences)\n2. Key Points (bullet list)\n3. Detailed Explanation\n4. Recommendations/Conclusions",
            "suffix": ""
        },
        "constraint_based": {
            "name": "Constraint-Based",
            "description": "Adds specific limitations",
            "template": "{prompt}\n\nConstraints:\n- Be concise (max 500 words)\n- Use simple language accessible to beginners\n- Include practical examples\n- Avoid jargon unless defined",
            "suffix": ""
        },
        "socratic": {
            "name": "Socratic Method",
            "description": "Uses questions to explore the topic",
            "template": "Let's explore this topic through guided inquiry:\n\n{prompt}\n\nFirst, consider these questions:\n1. What is the core problem/concept here?\n2. What are the underlying assumptions?\n3. What evidence supports different viewpoints?\n4. What are the implications of different approaches?",
            "suffix": ""
        },
        "tree_of_thought": {
            "name": "Tree of Thoughts (ToT)",
            "description": "Explores multiple reasoning paths",
            "template": "{prompt}\n\nApproach this by:\n1. Generating 3 different initial approaches\n2. Evaluating the strengths and weaknesses of each\n3. Selecting the most promising path\n4. Developing that path further\n5. Verifying the solution",
            "suffix": ""
        },
        "persona_based": {
            "name": "Multi-Persona Analysis",
            "description": "Analyzes from multiple perspectives",
            "template": "{prompt}\n\nAnalyze this from three perspectives:\n1. The Optimist: What are the best possible outcomes?\n2. The Skeptic: What could go wrong? What are the risks?\n3. The Pragmatist: What's the most realistic assessment?",
            "suffix": ""
        },
        "metacognitive": {
            "name": "Metacognitive Prompting",
            "description": "Encourages self-reflection",
            "template": "{prompt}\n\nAs you respond:\n- Identify what you know vs. what you're uncertain about\n- Note any assumptions you're making\n- Consider alternative interpretations\n- Rate your confidence level (1-10) for key claims",
            "suffix": ""
        },
        "decompositional": {
            "name": "Decomposition",
            "description": "Breaks complex tasks into subtasks",
            "template": "Let's break this down into manageable parts:\n\n{prompt}\n\nStep 1: Identify the main components\nStep 2: Address each component systematically\nStep 3: Integrate the solutions\nStep 4: Verify completeness",
            "suffix": ""
        }
    }

    TASK_CATEGORIES = {
        "coding": {
            "name": "Code Generation/Review",
            "system_prompt": "You are an expert software engineer with deep knowledge of best practices, design patterns, and clean code principles.",
            "enhancements": [
                "Include error handling and edge cases",
                "Add appropriate comments and documentation",
                "Follow language-specific conventions",
                "Consider performance implications",
                "Include example usage"
            ]
        },
        "writing": {
            "name": "Content Writing",
            "system_prompt": "You are a skilled writer with expertise in creating engaging, clear, and well-structured content.",
            "enhancements": [
                "Specify target audience",
                "Define desired tone and style",
                "Include SEO considerations if relevant",
                "Request specific length/format"
            ]
        },
        "analysis": {
            "name": "Data Analysis",
            "system_prompt": "You are a data analyst with expertise in extracting insights, identifying patterns, and presenting findings clearly.",
            "enhancements": [
                "Specify analysis methodology",
                "Request visualizations/charts description",
                "Include statistical significance considerations",
                "Request actionable recommendations"
            ]
        },
        "creative": {
            "name": "Creative Tasks",
            "system_prompt": "You are a creative professional with a unique perspective and ability to generate innovative ideas.",
            "enhancements": [
                "Encourage unconventional approaches",
                "Request multiple variations",
                "Include mood/atmosphere details",
                "Specify creative constraints for focus"
            ]
        },
        "research": {
            "name": "Research & Information",
            "system_prompt": "You are a research specialist skilled at synthesizing information from multiple sources and presenting balanced, well-cited analysis.",
            "enhancements": [
                "Request source citations",
                "Ask for multiple perspectives",
                "Include limitations/caveats",
                "Request recent/up-to-date information"
            ]
        },
        "problem_solving": {
            "name": "Problem Solving",
            "system_prompt": "You are a strategic problem solver with expertise in root cause analysis and developing effective solutions.",
            "enhancements": [
                "Define success criteria",
                "Request multiple solution options",
                "Include risk assessment",
                "Ask for implementation steps"
            ]
        },
        "education": {
            "name": "Educational Content",
            "system_prompt": "You are an experienced educator skilled at explaining complex concepts in accessible ways.",
            "enhancements": [
                "Specify learner level",
                "Include examples and analogies",
                "Add practice exercises",
                "Request comprehension checks"
            ]
        },
        "business": {
            "name": "Business & Strategy",
            "system_prompt": "You are a business strategist with expertise in market analysis, competitive positioning, and organizational development.",
            "enhancements": [
                "Include market context",
                "Request SWOT analysis",
                "Add financial considerations",
                "Include implementation timeline"
            ]
        }
    }


class PromptHistory:
    """Manages prompt history and favorites."""

    def __init__(self, storage_path: str):
        self.storage_path = Path(storage_path)
        self.storage_path.mkdir(parents=True, exist_ok=True)
        self.history_file = self.storage_path / "history.json"
        self.favorites_file = self.storage_path / "favorites.json"
        self.history: List[Dict] = []
        self.favorites: List[Dict] = []
        self.load()

    def load(self):
        """Load history and favorites from disk."""
        try:
            if self.history_file.exists():
                with open(self.history_file, 'r', encoding='utf-8') as f:
                    self.history = json.load(f)
        except Exception:
            self.history = []

        try:
            if self.favorites_file.exists():
                with open(self.favorites_file, 'r', encoding='utf-8') as f:
                    self.favorites = json.load(f)
        except Exception:
            self.favorites = []

    def save(self):
        """Save history and favorites to disk."""
        try:
            with open(self.history_file, 'w', encoding='utf-8') as f:
                json.dump(self.history[-100:], f, indent=2)  # Keep last 100
            with open(self.favorites_file, 'w', encoding='utf-8') as f:
                json.dump(self.favorites, f, indent=2)
        except Exception as e:
            print(f"Error saving history: {e}")

    def add_to_history(self, original: str, optimized: str, technique: str, category: str):
        """Add a prompt to history."""
        entry = {
            "timestamp": datetime.now().isoformat(),
            "original": original,
            "optimized": optimized,
            "technique": technique,
            "category": category
        }
        self.history.append(entry)
        self.save()

    def add_to_favorites(self, original: str, optimized: str, name: str = ""):
        """Add a prompt to favorites."""
        entry = {
            "timestamp": datetime.now().isoformat(),
            "name": name or f"Favorite {len(self.favorites) + 1}",
            "original": original,
            "optimized": optimized
        }
        self.favorites.append(entry)
        self.save()

    def remove_from_favorites(self, index: int):
        """Remove a prompt from favorites."""
        if 0 <= index < len(self.favorites):
            del self.favorites[index]
            self.save()


class APIProvider:
    """Base class for AI API providers."""

    def __init__(self, name: str, api_key: str = "", base_url: str = ""):
        self.name = name
        self.api_key = api_key
        self.base_url = base_url

    def optimize_prompt(self, prompt: str, system_prompt: str = "") -> str:
        raise NotImplementedError


class QwenProvider(APIProvider):
    """Qwen API provider."""

    def __init__(self):
        super().__init__("Qwen")
        self.credentials = self._load_credentials()

    def _load_credentials(self) -> Optional[Dict]:
        """Load Qwen credentials from config."""
        possible_paths = [
            Path.home() / ".qwen" / "oauth_creds.json",
            Path(os.environ.get("APPDATA", "")) / "qwen" / "oauth_creds.json",
            Path(os.environ.get("LOCALAPPDATA", "")) / "qwen" / "oauth_creds.json",
        ]

        for path in possible_paths:
            if path.exists():
                try:
                    with open(path, 'r', encoding='utf-8') as f:
                        return json.load(f)
                except Exception:
                    continue
        return None

    def optimize_prompt(self, prompt: str, system_prompt: str = "") -> str:
        """Call Qwen API to optimize prompt."""
        if not self.credentials or not HAS_REQUESTS:
            return ""

        access_token = self.credentials.get('access_token', '')
        resource_url = self.credentials.get('resource_url', 'portal.qwen.ai')

        headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json"
        }

        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        payload = {
            "model": "coder-model",
            "messages": messages,
            "max_tokens": 2000,
            "temperature": 0.7
        }

        try:
            response = requests.post(
                f"https://{resource_url}/v1/chat/completions",
                headers=headers,
                json=payload,
                timeout=60
            )

            if response.status_code == 200:
                data = response.json()
                if 'choices' in data and data['choices']:
                    return data['choices'][0].get('message', {}).get('content', '')
        except Exception as e:
            print(f"Qwen API error: {e}")

        return ""


class OpenAIProvider(APIProvider):
    """OpenAI API provider."""

    def __init__(self, api_key: str = ""):
        super().__init__("OpenAI", api_key, "https://api.openai.com/v1")

    def optimize_prompt(self, prompt: str, system_prompt: str = "") -> str:
        """Call OpenAI API to optimize prompt."""
        if not self.api_key or not HAS_REQUESTS:
            return ""

        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }

        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        payload = {
            "model": "gpt-4o",
            "messages": messages,
            "max_tokens": 2000,
            "temperature": 0.7
        }

        try:
            response = requests.post(
                f"{self.base_url}/chat/completions",
                headers=headers,
                json=payload,
                timeout=60
            )

            if response.status_code == 200:
                data = response.json()
                if 'choices' in data and data['choices']:
                    return data['choices'][0].get('message', {}).get('content', '')
        except Exception as e:
            print(f"OpenAI API error: {e}")

        return ""


class AnthropicProvider(APIProvider):
    """Anthropic API provider."""

    def __init__(self, api_key: str = ""):
        super().__init__("Anthropic", api_key, "https://api.anthropic.com/v1")

    def optimize_prompt(self, prompt: str, system_prompt: str = "") -> str:
        """Call Anthropic API to optimize prompt."""
        if not self.api_key or not HAS_REQUESTS:
            return ""

        headers = {
            "x-api-key": self.api_key,
            "Content-Type": "application/json",
            "anthropic-version": "2023-06-01"
        }

        payload = {
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 2000,
            "messages": [{"role": "user", "content": prompt}]
        }

        if system_prompt:
            payload["system"] = system_prompt

        try:
            response = requests.post(
                f"{self.base_url}/messages",
                headers=headers,
                json=payload,
                timeout=60
            )

            if response.status_code == 200:
                data = response.json()
                if 'content' in data and data['content']:
                    return data['content'][0].get('text', '')
        except Exception as e:
            print(f"Anthropic API error: {e}")

        return ""


class LocalOptimizer:
    """Local prompt optimization without API calls."""

    @staticmethod
    def optimize(prompt: str, technique: str, category: str) -> str:
        """Optimize prompt locally using templates."""
        tech = PromptEngineeringTechniques.TECHNIQUES.get(technique, {})
        cat = PromptEngineeringTechniques.TASK_CATEGORIES.get(category, {})

        result_parts = []

        # Add system context
        if cat.get('system_prompt'):
            result_parts.append(f"[CONTEXT]\n{cat['system_prompt']}\n")

        # Apply technique template
        if tech.get('template'):
            optimized = tech['template'].format(prompt=prompt, role="specialist in this domain")
        else:
            optimized = prompt

        result_parts.append(f"[TASK]\n{optimized}")

        # Add category-specific enhancements
        if cat.get('enhancements'):
            result_parts.append("\n[REQUIREMENTS]")
            for i, enhancement in enumerate(cat['enhancements'], 1):
                result_parts.append(f"{i}. {enhancement}")

        # Add output format
        result_parts.append("\n[OUTPUT FORMAT]")
        result_parts.append("Please provide a well-structured response that directly addresses the task.")

        return "\n".join(result_parts)


class PromptEngineerPro:
    """Main application class."""

    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Prompt Engineer Pro")
        self.root.geometry("1400x900")
        self.root.minsize(1000, 700)

        # Configure dark theme colors
        self.colors = {
            'bg': '#1e1e2e',
            'bg_secondary': '#2d2d3d',
            'bg_tertiary': '#3d3d4d',
            'text': '#cdd6f4',
            'text_secondary': '#a6adc8',
            'accent': '#89b4fa',
            'accent_hover': '#b4befe',
            'success': '#a6e3a1',
            'warning': '#f9e2af',
            'error': '#f38ba8',
            'border': '#45475a'
        }

        # Apply dark theme
        self.root.configure(bg=self.colors['bg'])
        self.style = ttk.Style()
        self.style.theme_use('clam')
        self._configure_styles()

        # Initialize components
        self.storage_path = Path.home() / ".prompt_engineer_pro"
        self.history = PromptHistory(str(self.storage_path))
        self.settings = self._load_settings()

        # Initialize providers
        self.providers = {
            'qwen': QwenProvider(),
            'openai': OpenAIProvider(self.settings.get('openai_api_key', '')),
            'anthropic': AnthropicProvider(self.settings.get('anthropic_api_key', '')),
            'local': None
        }

        # State variables
        self.current_technique = tk.StringVar(value='chain_of_thought')
        self.current_category = tk.StringVar(value='coding')
        self.current_provider = tk.StringVar(value='local')
        self.auto_copy = tk.BooleanVar(value=True)
        self.show_preview = tk.BooleanVar(value=True)

        # Build UI
        self._build_ui()

        # Bind keyboard shortcuts
        self._bind_shortcuts()

    def _configure_styles(self):
        """Configure ttk styles for dark theme."""
        self.style.configure('.',
            background=self.colors['bg'],
            foreground=self.colors['text'],
            fieldbackground=self.colors['bg_secondary'],
            bordercolor=self.colors['border']
        )

        self.style.configure('TFrame', background=self.colors['bg'])
        self.style.configure('TLabel', background=self.colors['bg'], foreground=self.colors['text'])
        self.style.configure('TButton',
            background=self.colors['accent'],
            foreground=self.colors['bg'],
            padding=(15, 8),
            font=('Segoe UI', 10, 'bold')
        )
        self.style.map('TButton',
            background=[('active', self.colors['accent_hover'])],
            foreground=[('active', self.colors['bg'])]
        )

        self.style.configure('Secondary.TButton',
            background=self.colors['bg_tertiary'],
            foreground=self.colors['text'],
            padding=(10, 6)
        )
        self.style.map('Secondary.TButton',
            background=[('active', self.colors['border'])]
        )

        self.style.configure('TCombobox',
            fieldbackground=self.colors['bg_secondary'],
            background=self.colors['bg_secondary'],
            foreground=self.colors['text'],
            arrowcolor=self.colors['text']
        )

        self.style.configure('TNotebook', background=self.colors['bg'])
        self.style.configure('TNotebook.Tab',
            background=self.colors['bg_secondary'],
            foreground=self.colors['text'],
            padding=(15, 8)
        )
        self.style.map('TNotebook.Tab',
            background=[('selected', self.colors['accent'])],
            foreground=[('selected', self.colors['bg'])]
        )

        self.style.configure('TCheckbutton',
            background=self.colors['bg'],
            foreground=self.colors['text']
        )

        self.style.configure('TLabelframe',
            background=self.colors['bg'],
            foreground=self.colors['text']
        )
        self.style.configure('TLabelframe.Label',
            background=self.colors['bg'],
            foreground=self.colors['accent']
        )

    def _load_settings(self) -> Dict:
        """Load application settings."""
        settings_file = self.storage_path / "settings.json"
        try:
            if settings_file.exists():
                with open(settings_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
        except Exception:
            pass
        return {}

    def _save_settings(self):
        """Save application settings."""
        settings_file = self.storage_path / "settings.json"
        self.storage_path.mkdir(parents=True, exist_ok=True)
        try:
            with open(settings_file, 'w', encoding='utf-8') as f:
                json.dump(self.settings, f, indent=2)
        except Exception as e:
            print(f"Error saving settings: {e}")

    def _build_ui(self):
        """Build the main user interface."""
        # Main container
        main_container = ttk.Frame(self.root, padding=10)
        main_container.pack(fill=tk.BOTH, expand=True)

        # Header
        self._build_header(main_container)

        # Content area with notebook
        self.notebook = ttk.Notebook(main_container)
        self.notebook.pack(fill=tk.BOTH, expand=True, pady=(10, 0))

        # Main tab - Prompt Optimization
        main_tab = ttk.Frame(self.notebook)
        self.notebook.add(main_tab, text="  Optimize  ")
        self._build_main_tab(main_tab)

        # Templates tab
        templates_tab = ttk.Frame(self.notebook)
        self.notebook.add(templates_tab, text="  Templates  ")
        self._build_templates_tab(templates_tab)

        # History tab
        history_tab = ttk.Frame(self.notebook)
        self.notebook.add(history_tab, text="  History  ")
        self._build_history_tab(history_tab)

        # Settings tab
        settings_tab = ttk.Frame(self.notebook)
        self.notebook.add(settings_tab, text="  Settings  ")
        self._build_settings_tab(settings_tab)

        # Status bar
        self._build_status_bar(main_container)

    def _build_header(self, parent):
        """Build the header section."""
        header_frame = ttk.Frame(parent)
        header_frame.pack(fill=tk.X, pady=(0, 10))

        # Title
        title_label = tk.Label(
            header_frame,
            text="Prompt Engineer Pro",
            font=('Segoe UI', 20, 'bold'),
            bg=self.colors['bg'],
            fg=self.colors['accent']
        )
        title_label.pack(side=tk.LEFT)

        # Subtitle
        subtitle_label = tk.Label(
            header_frame,
            text="Create the Perfect Prompt for Any AI Task",
            font=('Segoe UI', 10),
            bg=self.colors['bg'],
            fg=self.colors['text_secondary']
        )
        subtitle_label.pack(side=tk.LEFT, padx=(15, 0), pady=(8, 0))

    def _build_main_tab(self, parent):
        """Build the main optimization tab."""
        # Create horizontal paned window
        paned = ttk.PanedWindow(parent, orient=tk.HORIZONTAL)
        paned.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)

        # Left panel - Input and Options
        left_panel = ttk.Frame(paned)
        paned.add(left_panel, weight=1)

        # Options frame
        options_frame = ttk.LabelFrame(left_panel, text="Options", padding=10)
        options_frame.pack(fill=tk.X, pady=(0, 10))

        # Provider selection
        provider_frame = ttk.Frame(options_frame)
        provider_frame.pack(fill=tk.X, pady=(0, 8))

        ttk.Label(provider_frame, text="AI Provider:").pack(side=tk.LEFT)
        provider_combo = ttk.Combobox(
            provider_frame,
            textvariable=self.current_provider,
            values=['local', 'qwen', 'openai', 'anthropic'],
            state='readonly',
            width=15
        )
        provider_combo.pack(side=tk.LEFT, padx=(10, 0))

        # Category selection
        ttk.Label(provider_frame, text="Category:").pack(side=tk.LEFT, padx=(20, 0))
        category_combo = ttk.Combobox(
            provider_frame,
            textvariable=self.current_category,
            values=list(PromptEngineeringTechniques.TASK_CATEGORIES.keys()),
            state='readonly',
            width=15
        )
        category_combo.pack(side=tk.LEFT, padx=(10, 0))

        # Technique selection
        tech_frame = ttk.Frame(options_frame)
        tech_frame.pack(fill=tk.X, pady=(0, 8))

        ttk.Label(tech_frame, text="Technique:").pack(side=tk.LEFT)
        technique_combo = ttk.Combobox(
            tech_frame,
            textvariable=self.current_technique,
            values=list(PromptEngineeringTechniques.TECHNIQUES.keys()),
            state='readonly',
            width=20
        )
        technique_combo.pack(side=tk.LEFT, padx=(10, 0))
        technique_combo.bind('<<ComboboxSelected>>', self._on_technique_change)

        # Technique description
        self.technique_desc_label = tk.Label(
            tech_frame,
            text=PromptEngineeringTechniques.TECHNIQUES['chain_of_thought']['description'],
            font=('Segoe UI', 9, 'italic'),
            bg=self.colors['bg'],
            fg=self.colors['text_secondary']
        )
        self.technique_desc_label.pack(side=tk.LEFT, padx=(15, 0))

        # Checkboxes
        check_frame = ttk.Frame(options_frame)
        check_frame.pack(fill=tk.X)

        ttk.Checkbutton(check_frame, text="Auto-copy result", variable=self.auto_copy).pack(side=tk.LEFT)
        ttk.Checkbutton(check_frame, text="Show preview", variable=self.show_preview).pack(side=tk.LEFT, padx=(15, 0))

        # Input area
        input_frame = ttk.LabelFrame(left_panel, text="Your Prompt (Paste your text here)", padding=10)
        input_frame.pack(fill=tk.BOTH, expand=True)

        # Input text area with custom styling
        self.input_text = scrolledtext.ScrolledText(
            input_frame,
            wrap=tk.WORD,
            font=('Consolas', 11),
            bg=self.colors['bg_secondary'],
            fg=self.colors['text'],
            insertbackground=self.colors['text'],
            selectbackground=self.colors['accent'],
            selectforeground=self.colors['bg'],
            relief=tk.FLAT,
            padx=10,
            pady=10
        )
        self.input_text.pack(fill=tk.BOTH, expand=True)

        # Input toolbar
        input_toolbar = ttk.Frame(input_frame)
        input_toolbar.pack(fill=tk.X, pady=(10, 0))

        ttk.Button(input_toolbar, text="Paste", style='Secondary.TButton',
                  command=self._paste_input).pack(side=tk.LEFT)
        ttk.Button(input_toolbar, text="Clear", style='Secondary.TButton',
                  command=lambda: self.input_text.delete('1.0', tk.END)).pack(side=tk.LEFT, padx=(5, 0))
        ttk.Button(input_toolbar, text="Load File", style='Secondary.TButton',
                  command=self._load_from_file).pack(side=tk.LEFT, padx=(5, 0))

        self.input_char_count = tk.Label(
            input_toolbar,
            text="0 characters",
            font=('Segoe UI', 9),
            bg=self.colors['bg'],
            fg=self.colors['text_secondary']
        )
        self.input_char_count.pack(side=tk.RIGHT)

        # Bind text change event
        self.input_text.bind('<KeyRelease>', self._update_char_count)

        # Action buttons
        button_frame = ttk.Frame(left_panel)
        button_frame.pack(fill=tk.X, pady=10)

        self.optimize_btn = ttk.Button(
            button_frame,
            text="Optimize Prompt",
            command=self._optimize_prompt
        )
        self.optimize_btn.pack(side=tk.LEFT)

        ttk.Button(
            button_frame,
            text="Quick Enhance",
            style='Secondary.TButton',
            command=self._quick_enhance
        ).pack(side=tk.LEFT, padx=(10, 0))

        # Right panel - Output
        right_panel = ttk.Frame(paned)
        paned.add(right_panel, weight=1)

        # Output area
        output_frame = ttk.LabelFrame(right_panel, text="Optimized Prompt", padding=10)
        output_frame.pack(fill=tk.BOTH, expand=True)

        self.output_text = scrolledtext.ScrolledText(
            output_frame,
            wrap=tk.WORD,
            font=('Consolas', 11),
            bg=self.colors['bg_secondary'],
            fg=self.colors['success'],
            insertbackground=self.colors['text'],
            selectbackground=self.colors['accent'],
            selectforeground=self.colors['bg'],
            relief=tk.FLAT,
            padx=10,
            pady=10
        )
        self.output_text.pack(fill=tk.BOTH, expand=True)

        # Output toolbar
        output_toolbar = ttk.Frame(output_frame)
        output_toolbar.pack(fill=tk.X, pady=(10, 0))

        ttk.Button(output_toolbar, text="Copy", style='Secondary.TButton',
                  command=self._copy_output).pack(side=tk.LEFT)
        ttk.Button(output_toolbar, text="Save", style='Secondary.TButton',
                  command=self._save_to_file).pack(side=tk.LEFT, padx=(5, 0))
        ttk.Button(output_toolbar, text="Add to Favorites", style='Secondary.TButton',
                  command=self._add_to_favorites).pack(side=tk.LEFT, padx=(5, 0))

        self.output_char_count = tk.Label(
            output_toolbar,
            text="0 characters",
            font=('Segoe UI', 9),
            bg=self.colors['bg'],
            fg=self.colors['text_secondary']
        )
        self.output_char_count.pack(side=tk.RIGHT)

    def _build_templates_tab(self, parent):
        """Build the templates tab."""
        # Left side - Categories
        left_frame = ttk.Frame(parent)
        left_frame.pack(side=tk.LEFT, fill=tk.Y, padx=10, pady=10)

        ttk.Label(left_frame, text="Categories", font=('Segoe UI', 12, 'bold')).pack(anchor=tk.W)

        self.category_listbox = tk.Listbox(
            left_frame,
            font=('Segoe UI', 10),
            bg=self.colors['bg_secondary'],
            fg=self.colors['text'],
            selectbackground=self.colors['accent'],
            selectforeground=self.colors['bg'],
            relief=tk.FLAT,
            width=25,
            height=20
        )
        self.category_listbox.pack(fill=tk.Y, expand=True, pady=(10, 0))

        for cat_id, cat_info in PromptEngineeringTechniques.TASK_CATEGORIES.items():
            self.category_listbox.insert(tk.END, f"  {cat_info['name']}")

        self.category_listbox.bind('<<ListboxSelect>>', self._on_category_select)

        # Right side - Template details
        right_frame = ttk.Frame(parent)
        right_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=10, pady=10)

        ttk.Label(right_frame, text="Template Details", font=('Segoe UI', 12, 'bold')).pack(anchor=tk.W)

        self.template_details = scrolledtext.ScrolledText(
            right_frame,
            wrap=tk.WORD,
            font=('Consolas', 10),
            bg=self.colors['bg_secondary'],
            fg=self.colors['text'],
            relief=tk.FLAT,
            padx=10,
            pady=10
        )
        self.template_details.pack(fill=tk.BOTH, expand=True, pady=(10, 0))

        # Template action buttons
        template_buttons = ttk.Frame(right_frame)
        template_buttons.pack(fill=tk.X, pady=(10, 0))

        ttk.Button(template_buttons, text="Use This Template",
                  command=self._use_template).pack(side=tk.LEFT)
        ttk.Button(template_buttons, text="Copy Template", style='Secondary.TButton',
                  command=self._copy_template).pack(side=tk.LEFT, padx=(10, 0))

    def _build_history_tab(self, parent):
        """Build the history tab."""
        # Create notebook for History/Favorites
        history_notebook = ttk.Notebook(parent)
        history_notebook.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

        # History sub-tab
        history_frame = ttk.Frame(history_notebook)
        history_notebook.add(history_frame, text="  Recent  ")

        self.history_listbox = tk.Listbox(
            history_frame,
            font=('Segoe UI', 10),
            bg=self.colors['bg_secondary'],
            fg=self.colors['text'],
            selectbackground=self.colors['accent'],
            selectforeground=self.colors['bg'],
            relief=tk.FLAT
        )
        self.history_listbox.pack(fill=tk.BOTH, expand=True, pady=10)
        self.history_listbox.bind('<<ListboxSelect>>', self._on_history_select)

        history_buttons = ttk.Frame(history_frame)
        history_buttons.pack(fill=tk.X)

        ttk.Button(history_buttons, text="Load Selected",
                  command=self._load_from_history).pack(side=tk.LEFT)
        ttk.Button(history_buttons, text="Clear History", style='Secondary.TButton',
                  command=self._clear_history).pack(side=tk.LEFT, padx=(10, 0))

        # Favorites sub-tab
        favorites_frame = ttk.Frame(history_notebook)
        history_notebook.add(favorites_frame, text="  Favorites  ")

        self.favorites_listbox = tk.Listbox(
            favorites_frame,
            font=('Segoe UI', 10),
            bg=self.colors['bg_secondary'],
            fg=self.colors['text'],
            selectbackground=self.colors['accent'],
            selectforeground=self.colors['bg'],
            relief=tk.FLAT
        )
        self.favorites_listbox.pack(fill=tk.BOTH, expand=True, pady=10)
        self.favorites_listbox.bind('<<ListboxSelect>>', self._on_favorites_select)

        favorites_buttons = ttk.Frame(favorites_frame)
        favorites_buttons.pack(fill=tk.X)

        ttk.Button(favorites_buttons, text="Load Selected",
                  command=self._load_from_favorites).pack(side=tk.LEFT)
        ttk.Button(favorites_buttons, text="Remove Selected", style='Secondary.TButton',
                  command=self._remove_favorite).pack(side=tk.LEFT, padx=(10, 0))

        # Refresh history display
        self._refresh_history_display()

    def _build_settings_tab(self, parent):
        """Build the settings tab."""
        settings_container = ttk.Frame(parent, padding=20)
        settings_container.pack(fill=tk.BOTH, expand=True)

        # API Keys section
        api_frame = ttk.LabelFrame(settings_container, text="API Keys", padding=15)
        api_frame.pack(fill=tk.X, pady=(0, 15))

        # OpenAI
        openai_frame = ttk.Frame(api_frame)
        openai_frame.pack(fill=tk.X, pady=(0, 10))

        ttk.Label(openai_frame, text="OpenAI API Key:", width=20).pack(side=tk.LEFT)
        self.openai_key_entry = ttk.Entry(openai_frame, width=50, show="*")
        self.openai_key_entry.pack(side=tk.LEFT, padx=(10, 0))
        self.openai_key_entry.insert(0, self.settings.get('openai_api_key', ''))

        # Anthropic
        anthropic_frame = ttk.Frame(api_frame)
        anthropic_frame.pack(fill=tk.X, pady=(0, 10))

        ttk.Label(anthropic_frame, text="Anthropic API Key:", width=20).pack(side=tk.LEFT)
        self.anthropic_key_entry = ttk.Entry(anthropic_frame, width=50, show="*")
        self.anthropic_key_entry.pack(side=tk.LEFT, padx=(10, 0))
        self.anthropic_key_entry.insert(0, self.settings.get('anthropic_api_key', ''))

        # Qwen info
        qwen_frame = ttk.Frame(api_frame)
        qwen_frame.pack(fill=tk.X)

        qwen_status = "Configured" if self.providers['qwen'].credentials else "Not found"
        qwen_color = self.colors['success'] if self.providers['qwen'].credentials else self.colors['error']

        ttk.Label(qwen_frame, text="Qwen Credentials:", width=20).pack(side=tk.LEFT)
        tk.Label(
            qwen_frame,
            text=qwen_status,
            font=('Segoe UI', 10),
            bg=self.colors['bg'],
            fg=qwen_color
        ).pack(side=tk.LEFT, padx=(10, 0))

        # Preferences section
        prefs_frame = ttk.LabelFrame(settings_container, text="Preferences", padding=15)
        prefs_frame.pack(fill=tk.X, pady=(0, 15))

        ttk.Checkbutton(prefs_frame, text="Auto-copy optimized prompt to clipboard",
                       variable=self.auto_copy).pack(anchor=tk.W)
        ttk.Checkbutton(prefs_frame, text="Show technique preview",
                       variable=self.show_preview).pack(anchor=tk.W, pady=(5, 0))

        # Save button
        save_frame = ttk.Frame(settings_container)
        save_frame.pack(fill=tk.X)

        ttk.Button(save_frame, text="Save Settings",
                  command=self._save_api_settings).pack(side=tk.LEFT)

        self.settings_status = tk.Label(
            save_frame,
            text="",
            font=('Segoe UI', 10),
            bg=self.colors['bg'],
            fg=self.colors['success']
        )
        self.settings_status.pack(side=tk.LEFT, padx=(15, 0))

    def _build_status_bar(self, parent):
        """Build the status bar."""
        status_frame = ttk.Frame(parent)
        status_frame.pack(fill=tk.X, pady=(10, 0))

        self.status_label = tk.Label(
            status_frame,
            text="Ready",
            font=('Segoe UI', 9),
            bg=self.colors['bg'],
            fg=self.colors['text_secondary'],
            anchor=tk.W
        )
        self.status_label.pack(side=tk.LEFT)

        # Version info
        version_label = tk.Label(
            status_frame,
            text="v1.0.0",
            font=('Segoe UI', 9),
            bg=self.colors['bg'],
            fg=self.colors['text_secondary']
        )
        version_label.pack(side=tk.RIGHT)

    def _bind_shortcuts(self):
        """Bind keyboard shortcuts."""
        self.root.bind('<Control-Return>', lambda e: self._optimize_prompt())
        self.root.bind('<Control-v>', lambda e: self._paste_input())
        self.root.bind('<Control-c>', lambda e: self._copy_output())
        self.root.bind('<Control-s>', lambda e: self._save_to_file())
        self.root.bind('<F5>', lambda e: self._optimize_prompt())

    def _update_char_count(self, event=None):
        """Update character count label."""
        text = self.input_text.get('1.0', tk.END).strip()
        count = len(text)
        words = len(text.split()) if text else 0
        self.input_char_count.config(text=f"{count} chars, {words} words")

    def _update_output_char_count(self):
        """Update output character count."""
        text = self.output_text.get('1.0', tk.END).strip()
        count = len(text)
        words = len(text.split()) if text else 0
        self.output_char_count.config(text=f"{count} chars, {words} words")

    def _on_technique_change(self, event=None):
        """Handle technique selection change."""
        technique = self.current_technique.get()
        tech_info = PromptEngineeringTechniques.TECHNIQUES.get(technique, {})
        self.technique_desc_label.config(text=tech_info.get('description', ''))

    def _on_category_select(self, event=None):
        """Handle category selection in templates tab."""
        selection = self.category_listbox.curselection()
        if not selection:
            return

        cat_ids = list(PromptEngineeringTechniques.TASK_CATEGORIES.keys())
        cat_id = cat_ids[selection[0]]
        cat_info = PromptEngineeringTechniques.TASK_CATEGORIES[cat_id]

        # Display template details
        self.template_details.delete('1.0', tk.END)

        details = f"Category: {cat_info['name']}\n"
        details += "=" * 50 + "\n\n"
        details += f"System Prompt:\n{cat_info['system_prompt']}\n\n"
        details += "Enhancements:\n"
        for i, enh in enumerate(cat_info['enhancements'], 1):
            details += f"  {i}. {enh}\n"

        self.template_details.insert('1.0', details)

    def _paste_input(self):
        """Paste from clipboard to input."""
        try:
            if HAS_PYPERCLIP:
                text = pyperclip.paste()
            else:
                text = self.root.clipboard_get()
            self.input_text.delete('1.0', tk.END)
            self.input_text.insert('1.0', text)
            self._update_char_count()
            self._set_status("Pasted from clipboard")
        except Exception as e:
            self._set_status(f"Paste failed: {e}", error=True)

    def _copy_output(self):
        """Copy output to clipboard."""
        text = self.output_text.get('1.0', tk.END).strip()
        if not text:
            self._set_status("Nothing to copy", error=True)
            return

        try:
            if HAS_PYPERCLIP:
                pyperclip.copy(text)
            else:
                self.root.clipboard_clear()
                self.root.clipboard_append(text)
            self._set_status("Copied to clipboard!")
        except Exception as e:
            self._set_status(f"Copy failed: {e}", error=True)

    def _load_from_file(self):
        """Load prompt from file."""
        file_path = filedialog.askopenfilename(
            filetypes=[("Text files", "*.txt"), ("All files", "*.*")]
        )
        if file_path:
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                self.input_text.delete('1.0', tk.END)
                self.input_text.insert('1.0', content)
                self._update_char_count()
                self._set_status(f"Loaded from {Path(file_path).name}")
            except Exception as e:
                self._set_status(f"Load failed: {e}", error=True)

    def _save_to_file(self):
        """Save optimized prompt to file."""
        text = self.output_text.get('1.0', tk.END).strip()
        if not text:
            self._set_status("Nothing to save", error=True)
            return

        file_path = filedialog.asksaveasfilename(
            defaultextension=".txt",
            filetypes=[("Text files", "*.txt"), ("All files", "*.*")]
        )
        if file_path:
            try:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(text)
                self._set_status(f"Saved to {Path(file_path).name}")
            except Exception as e:
                self._set_status(f"Save failed: {e}", error=True)

    def _optimize_prompt(self):
        """Optimize the prompt using selected provider and technique."""
        input_text = self.input_text.get('1.0', tk.END).strip()
        if not input_text:
            self._set_status("Please enter a prompt to optimize", error=True)
            return

        self._set_status("Optimizing...")
        self.optimize_btn.config(state='disabled')

        # Run optimization in thread to avoid blocking UI
        def optimize_thread():
            try:
                provider_name = self.current_provider.get()
                technique = self.current_technique.get()
                category = self.current_category.get()

                # Build the optimization prompt
                tech_info = PromptEngineeringTechniques.TECHNIQUES.get(technique, {})
                cat_info = PromptEngineeringTechniques.TASK_CATEGORIES.get(category, {})

                system_prompt = f"""You are an expert prompt engineer. Your task is to optimize the given prompt to be maximally effective.

Context: This prompt is for {cat_info.get('name', 'general')} tasks.
Technique to apply: {tech_info.get('name', 'general optimization')} - {tech_info.get('description', '')}

Guidelines:
1. Make the prompt clear, specific, and actionable
2. Apply the {tech_info.get('name', '')} technique appropriately
3. Include relevant context and constraints
4. Specify expected output format
5. Add any helpful examples if appropriate

Return ONLY the optimized prompt, no explanations."""

                optimization_request = f"""Please optimize this prompt for maximum effectiveness:

ORIGINAL PROMPT:
{input_text}

Apply the {tech_info.get('name', '')} technique and optimize for {cat_info.get('name', '')} tasks."""

                result = None

                if provider_name == 'local':
                    result = LocalOptimizer.optimize(input_text, technique, category)
                elif provider_name == 'qwen':
                    provider = self.providers['qwen']
                    result = provider.optimize_prompt(optimization_request, system_prompt)
                elif provider_name == 'openai':
                    provider = self.providers['openai']
                    result = provider.optimize_prompt(optimization_request, system_prompt)
                elif provider_name == 'anthropic':
                    provider = self.providers['anthropic']
                    result = provider.optimize_prompt(optimization_request, system_prompt)

                if not result:
                    # Fallback to local optimization
                    result = LocalOptimizer.optimize(input_text, technique, category)

                # Update UI in main thread
                self.root.after(0, lambda: self._display_result(result, input_text, technique, category))

            except Exception as e:
                self.root.after(0, lambda: self._set_status(f"Error: {e}", error=True))
            finally:
                self.root.after(0, lambda: self.optimize_btn.config(state='normal'))

        thread = threading.Thread(target=optimize_thread, daemon=True)
        thread.start()

    def _display_result(self, result: str, original: str, technique: str, category: str):
        """Display optimization result."""
        self.output_text.delete('1.0', tk.END)
        self.output_text.insert('1.0', result)
        self._update_output_char_count()

        # Add to history
        self.history.add_to_history(original, result, technique, category)
        self._refresh_history_display()

        # Auto-copy if enabled
        if self.auto_copy.get():
            self._copy_output()
            self._set_status("Optimized and copied to clipboard!")
        else:
            self._set_status("Optimization complete!")

    def _quick_enhance(self):
        """Quick enhancement without full optimization."""
        input_text = self.input_text.get('1.0', tk.END).strip()
        if not input_text:
            self._set_status("Please enter a prompt to enhance", error=True)
            return

        # Quick enhancements
        enhanced = input_text

        # Add clarity markers
        if not enhanced.endswith(('.', '?', '!')):
            enhanced += '.'

        # Add structure if missing
        if '\n' not in enhanced and len(enhanced) > 200:
            sentences = enhanced.replace('. ', '.\n\n')
            enhanced = sentences

        # Add output specification if not present
        output_keywords = ['output', 'format', 'return', 'provide', 'give me', 'response']
        if not any(kw in enhanced.lower() for kw in output_keywords):
            enhanced += "\n\nPlease provide a clear, well-structured response."

        self.output_text.delete('1.0', tk.END)
        self.output_text.insert('1.0', enhanced)
        self._update_output_char_count()
        self._set_status("Quick enhancement applied")

    def _add_to_favorites(self):
        """Add current prompt to favorites."""
        original = self.input_text.get('1.0', tk.END).strip()
        optimized = self.output_text.get('1.0', tk.END).strip()

        if not optimized:
            self._set_status("No optimized prompt to save", error=True)
            return

        # Simple dialog for name
        name = f"Prompt {len(self.history.favorites) + 1}"
        self.history.add_to_favorites(original, optimized, name)
        self._refresh_history_display()
        self._set_status("Added to favorites!")

    def _refresh_history_display(self):
        """Refresh the history and favorites listboxes."""
        # Update history listbox
        self.history_listbox.delete(0, tk.END)
        for entry in reversed(self.history.history[-50:]):  # Show last 50
            timestamp = entry.get('timestamp', '')[:16]
            preview = entry.get('original', '')[:50].replace('\n', ' ')
            self.history_listbox.insert(tk.END, f"  {timestamp} - {preview}...")

        # Update favorites listbox
        self.favorites_listbox.delete(0, tk.END)
        for entry in self.history.favorites:
            name = entry.get('name', 'Unnamed')
            preview = entry.get('optimized', '')[:40].replace('\n', ' ')
            self.favorites_listbox.insert(tk.END, f"  {name}: {preview}...")

    def _on_history_select(self, event=None):
        """Handle history selection."""
        pass  # Could show preview

    def _on_favorites_select(self, event=None):
        """Handle favorites selection."""
        pass  # Could show preview

    def _load_from_history(self):
        """Load selected history item."""
        selection = self.history_listbox.curselection()
        if not selection:
            return

        # Get from reversed list
        idx = len(self.history.history) - 1 - selection[0]
        if 0 <= idx < len(self.history.history):
            entry = self.history.history[idx]
            self.input_text.delete('1.0', tk.END)
            self.input_text.insert('1.0', entry.get('original', ''))
            self.output_text.delete('1.0', tk.END)
            self.output_text.insert('1.0', entry.get('optimized', ''))
            self._update_char_count()
            self._update_output_char_count()
            self.notebook.select(0)  # Switch to main tab
            self._set_status("Loaded from history")

    def _load_from_favorites(self):
        """Load selected favorite."""
        selection = self.favorites_listbox.curselection()
        if not selection:
            return

        entry = self.history.favorites[selection[0]]
        self.input_text.delete('1.0', tk.END)
        self.input_text.insert('1.0', entry.get('original', ''))
        self.output_text.delete('1.0', tk.END)
        self.output_text.insert('1.0', entry.get('optimized', ''))
        self._update_char_count()
        self._update_output_char_count()
        self.notebook.select(0)  # Switch to main tab
        self._set_status("Loaded from favorites")

    def _remove_favorite(self):
        """Remove selected favorite."""
        selection = self.favorites_listbox.curselection()
        if not selection:
            return

        self.history.remove_from_favorites(selection[0])
        self._refresh_history_display()
        self._set_status("Removed from favorites")

    def _clear_history(self):
        """Clear all history."""
        if messagebox.askyesno("Clear History", "Are you sure you want to clear all history?"):
            self.history.history = []
            self.history.save()
            self._refresh_history_display()
            self._set_status("History cleared")

    def _use_template(self):
        """Use selected template category."""
        selection = self.category_listbox.curselection()
        if not selection:
            return

        cat_ids = list(PromptEngineeringTechniques.TASK_CATEGORIES.keys())
        cat_id = cat_ids[selection[0]]
        self.current_category.set(cat_id)
        self.notebook.select(0)  # Switch to main tab
        self._set_status(f"Category set to {cat_id}")

    def _copy_template(self):
        """Copy template to clipboard."""
        text = self.template_details.get('1.0', tk.END).strip()
        if text:
            try:
                if HAS_PYPERCLIP:
                    pyperclip.copy(text)
                else:
                    self.root.clipboard_clear()
                    self.root.clipboard_append(text)
                self._set_status("Template copied!")
            except Exception:
                pass

    def _save_api_settings(self):
        """Save API settings."""
        self.settings['openai_api_key'] = self.openai_key_entry.get()
        self.settings['anthropic_api_key'] = self.anthropic_key_entry.get()
        self._save_settings()

        # Update providers
        self.providers['openai'] = OpenAIProvider(self.settings.get('openai_api_key', ''))
        self.providers['anthropic'] = AnthropicProvider(self.settings.get('anthropic_api_key', ''))

        self.settings_status.config(text="Settings saved!")
        self.root.after(3000, lambda: self.settings_status.config(text=""))

    def _set_status(self, message: str, error: bool = False):
        """Set status bar message."""
        color = self.colors['error'] if error else self.colors['text_secondary']
        self.status_label.config(text=message, fg=color)

    def run(self):
        """Start the application."""
        self.root.mainloop()


def main():
    """Main entry point."""
    app = PromptEngineerPro()
    app.run()


if __name__ == "__main__":
    main()
