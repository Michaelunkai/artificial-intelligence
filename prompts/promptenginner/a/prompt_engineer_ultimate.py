"""
Prompt Engineer Ultimate - The Most Advanced Prompt Engineering Tool
A professional-grade GUI application for creating, analyzing, and optimizing AI prompts.
Features: Large text handling, real-time analysis, multi-provider AI optimization,
prompt scoring, templates library, history management, and more.
"""

import os
import sys
import json
import threading
import time
import re
import hashlib
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, List, Any, Tuple
from dataclasses import dataclass, field, asdict
from enum import Enum
import tkinter as tk
from tkinter import ttk, messagebox, filedialog
from tkinter.font import Font
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


class PromptQuality(Enum):
    """Prompt quality levels."""
    POOR = 1
    FAIR = 2
    GOOD = 3
    EXCELLENT = 4
    OUTSTANDING = 5


@dataclass
class PromptAnalysis:
    """Analysis results for a prompt."""
    clarity_score: float = 0.0
    specificity_score: float = 0.0
    structure_score: float = 0.0
    actionability_score: float = 0.0
    context_score: float = 0.0
    overall_score: float = 0.0
    quality: PromptQuality = PromptQuality.POOR
    issues: List[str] = field(default_factory=list)
    suggestions: List[str] = field(default_factory=list)
    word_count: int = 0
    char_count: int = 0
    sentence_count: int = 0
    has_clear_objective: bool = False
    has_context: bool = False
    has_constraints: bool = False
    has_output_format: bool = False
    has_examples: bool = False


class PromptAnalyzer:
    """Advanced prompt analysis engine."""

    # Keywords indicating good prompt structure
    OBJECTIVE_KEYWORDS = [
        'create', 'write', 'generate', 'build', 'design', 'develop', 'implement',
        'analyze', 'explain', 'describe', 'summarize', 'compare', 'evaluate',
        'help me', 'i need', 'i want', 'please', 'can you', 'could you'
    ]

    CONTEXT_KEYWORDS = [
        'context:', 'background:', 'situation:', 'scenario:', 'given that',
        'considering', 'in the context of', 'for a', 'working on', 'project'
    ]

    CONSTRAINT_KEYWORDS = [
        'constraint', 'limit', 'maximum', 'minimum', 'must', 'should', 'avoid',
        'do not', "don't", 'only', 'exactly', 'no more than', 'at least',
        'requirement', 'rule', 'restriction'
    ]

    OUTPUT_FORMAT_KEYWORDS = [
        'format:', 'output:', 'return', 'provide', 'give me', 'respond with',
        'in json', 'as a list', 'as bullet points', 'in markdown', 'structured',
        'step by step', 'numbered', 'table', 'code block'
    ]

    EXAMPLE_KEYWORDS = [
        'example:', 'for example', 'such as', 'like this:', 'e.g.', 'sample',
        'instance', 'illustration', 'here is an example', 'input:', 'output:'
    ]

    WEAK_PHRASES = [
        'maybe', 'perhaps', 'kind of', 'sort of', 'i think', 'possibly',
        'might', 'could be', 'not sure', 'something like'
    ]

    @classmethod
    def analyze(cls, prompt: str) -> PromptAnalysis:
        """Perform comprehensive prompt analysis."""
        if not prompt or not prompt.strip():
            return PromptAnalysis()

        prompt_lower = prompt.lower()
        words = prompt.split()
        sentences = [s.strip() for s in re.split(r'[.!?]+', prompt) if s.strip()]

        analysis = PromptAnalysis(
            word_count=len(words),
            char_count=len(prompt),
            sentence_count=len(sentences)
        )

        # Check for clear objective
        analysis.has_clear_objective = any(kw in prompt_lower for kw in cls.OBJECTIVE_KEYWORDS)

        # Check for context
        analysis.has_context = any(kw in prompt_lower for kw in cls.CONTEXT_KEYWORDS)

        # Check for constraints
        analysis.has_constraints = any(kw in prompt_lower for kw in cls.CONSTRAINT_KEYWORDS)

        # Check for output format specification
        analysis.has_output_format = any(kw in prompt_lower for kw in cls.OUTPUT_FORMAT_KEYWORDS)

        # Check for examples
        analysis.has_examples = any(kw in prompt_lower for kw in cls.EXAMPLE_KEYWORDS)

        # Calculate individual scores
        analysis.clarity_score = cls._calculate_clarity_score(prompt, prompt_lower, words, sentences)
        analysis.specificity_score = cls._calculate_specificity_score(prompt, prompt_lower, words)
        analysis.structure_score = cls._calculate_structure_score(prompt, sentences, analysis)
        analysis.actionability_score = cls._calculate_actionability_score(prompt_lower, analysis)
        analysis.context_score = cls._calculate_context_score(prompt_lower, analysis)

        # Calculate overall score (weighted average)
        analysis.overall_score = (
            analysis.clarity_score * 0.25 +
            analysis.specificity_score * 0.25 +
            analysis.structure_score * 0.20 +
            analysis.actionability_score * 0.15 +
            analysis.context_score * 0.15
        )

        # Determine quality level
        if analysis.overall_score >= 90:
            analysis.quality = PromptQuality.OUTSTANDING
        elif analysis.overall_score >= 75:
            analysis.quality = PromptQuality.EXCELLENT
        elif analysis.overall_score >= 60:
            analysis.quality = PromptQuality.GOOD
        elif analysis.overall_score >= 40:
            analysis.quality = PromptQuality.FAIR
        else:
            analysis.quality = PromptQuality.POOR

        # Generate issues and suggestions
        cls._generate_feedback(analysis, prompt_lower)

        return analysis

    @classmethod
    def _calculate_clarity_score(cls, prompt: str, prompt_lower: str, words: list, sentences: list) -> float:
        """Calculate clarity score based on readability and clear language."""
        score = 50.0  # Base score

        # Check for weak/vague phrases (penalize)
        weak_count = sum(1 for phrase in cls.WEAK_PHRASES if phrase in prompt_lower)
        score -= weak_count * 5

        # Reward proper sentence structure
        if sentences and len(sentences) > 0:
            avg_sentence_length = len(words) / len(sentences)
            if 10 <= avg_sentence_length <= 25:
                score += 15
            elif avg_sentence_length < 10:
                score += 5

        # Reward proper punctuation
        if prompt.endswith(('.', '?', '!')):
            score += 10

        # Check for question format (often clearer)
        if '?' in prompt:
            score += 10

        # Reward proper capitalization at start
        if prompt and prompt[0].isupper():
            score += 5

        # Penalize excessive use of caps
        caps_ratio = sum(1 for c in prompt if c.isupper()) / max(len(prompt), 1)
        if caps_ratio > 0.3:
            score -= 15

        # Reward lists/bullet points
        if any(marker in prompt for marker in ['\n-', '\n*', '\n1.', '\n1)', '• ']):
            score += 10

        return max(0, min(100, score))

    @classmethod
    def _calculate_specificity_score(cls, prompt: str, prompt_lower: str, words: list) -> float:
        """Calculate specificity score based on details and precision."""
        score = 40.0  # Base score

        # Reward longer, more detailed prompts
        if len(words) >= 20:
            score += 15
        elif len(words) >= 10:
            score += 10
        elif len(words) < 5:
            score -= 15

        # Check for numbers (specific quantities)
        if re.search(r'\d+', prompt):
            score += 10

        # Check for specific technical terms
        technical_patterns = [
            r'\b(api|json|xml|html|css|sql|python|javascript|react|node)\b',
            r'\b(function|class|method|variable|parameter|argument)\b',
            r'\b(database|server|client|frontend|backend|endpoint)\b'
        ]
        for pattern in technical_patterns:
            if re.search(pattern, prompt_lower):
                score += 5
                break

        # Reward specific formatting requests
        if any(fmt in prompt_lower for fmt in ['markdown', 'json', 'csv', 'table', 'list']):
            score += 10

        # Reward time/scope constraints
        if any(time_word in prompt_lower for time_word in ['minute', 'hour', 'day', 'week', 'deadline']):
            score += 5

        # Check for quantitative requirements
        if any(quant in prompt_lower for quant in ['exactly', 'at least', 'no more than', 'between']):
            score += 10

        return max(0, min(100, score))

    @classmethod
    def _calculate_structure_score(cls, prompt: str, sentences: list, analysis: PromptAnalysis) -> float:
        """Calculate structure score based on organization."""
        score = 40.0  # Base score

        # Reward multiple sentences
        if len(sentences) >= 3:
            score += 15
        elif len(sentences) >= 2:
            score += 10

        # Reward line breaks (indicates structure)
        line_count = len(prompt.split('\n'))
        if line_count >= 3:
            score += 15
        elif line_count >= 2:
            score += 10

        # Reward section headers
        if re.search(r'^[A-Z][A-Za-z\s]+:', prompt, re.MULTILINE):
            score += 15

        # Reward numbered lists
        if re.search(r'^\d+[\.\)]\s', prompt, re.MULTILINE):
            score += 10

        # Reward having multiple components
        components = sum([
            analysis.has_clear_objective,
            analysis.has_context,
            analysis.has_constraints,
            analysis.has_output_format,
            analysis.has_examples
        ])
        score += components * 5

        return max(0, min(100, score))

    @classmethod
    def _calculate_actionability_score(cls, prompt_lower: str, analysis: PromptAnalysis) -> float:
        """Calculate actionability score based on clear action items."""
        score = 40.0  # Base score

        # Reward clear objective
        if analysis.has_clear_objective:
            score += 25

        # Reward output format specification
        if analysis.has_output_format:
            score += 20

        # Reward imperative verbs at start
        imperative_starters = ['create', 'write', 'build', 'make', 'generate', 'design',
                             'develop', 'explain', 'analyze', 'describe', 'list', 'provide']
        words = prompt_lower.split()
        if words and any(words[0].startswith(verb) for verb in imperative_starters):
            score += 15

        return max(0, min(100, score))

    @classmethod
    def _calculate_context_score(cls, prompt_lower: str, analysis: PromptAnalysis) -> float:
        """Calculate context score based on background information."""
        score = 40.0  # Base score

        # Reward context presence
        if analysis.has_context:
            score += 25

        # Reward constraints
        if analysis.has_constraints:
            score += 15

        # Reward examples
        if analysis.has_examples:
            score += 20

        # Check for role/persona specification
        if any(role in prompt_lower for role in ['you are', 'act as', 'pretend', 'role:', 'persona:']):
            score += 15

        return max(0, min(100, score))

    @classmethod
    def _generate_feedback(cls, analysis: PromptAnalysis, prompt_lower: str) -> None:
        """Generate issues and suggestions based on analysis."""
        # Issues
        if analysis.word_count < 5:
            analysis.issues.append("Prompt is too short - lacks detail")

        if not analysis.has_clear_objective:
            analysis.issues.append("No clear objective or action verb detected")

        weak_found = [p for p in cls.WEAK_PHRASES if p in prompt_lower]
        if weak_found:
            analysis.issues.append(f"Contains vague language: {', '.join(weak_found[:3])}")

        if analysis.clarity_score < 50:
            analysis.issues.append("Clarity could be improved")

        # Suggestions
        if not analysis.has_output_format:
            analysis.suggestions.append("Add output format specification (e.g., 'Respond in JSON format')")

        if not analysis.has_context:
            analysis.suggestions.append("Add context or background information")

        if not analysis.has_constraints:
            analysis.suggestions.append("Add constraints or requirements (e.g., word limits, style)")

        if not analysis.has_examples:
            analysis.suggestions.append("Consider adding examples for clarity")

        if analysis.sentence_count < 2:
            analysis.suggestions.append("Break into multiple sentences for better structure")

        if analysis.overall_score < 60:
            analysis.suggestions.append("Consider using a prompt template for better results")


class PromptEngineeringTechniques:
    """Collection of advanced prompt engineering techniques."""

    TECHNIQUES = {
        "chain_of_thought": {
            "name": "Chain of Thought (CoT)",
            "description": "Encourages step-by-step reasoning for complex problems",
            "best_for": ["Problem solving", "Math", "Logic", "Analysis"],
            "template": """[TASK]
{prompt}

[APPROACH]
Let's work through this systematically:
1. First, identify the key components of this problem
2. Break down each component
3. Analyze relationships between components
4. Synthesize findings
5. Draw conclusions

Please think through this step-by-step, showing your reasoning at each stage before providing your final answer.""",
            "suffix": "\n\nThink step by step and show your work."
        },
        "few_shot": {
            "name": "Few-Shot Learning",
            "description": "Provides examples to guide the response pattern",
            "best_for": ["Pattern matching", "Classification", "Format adherence"],
            "template": """I'll demonstrate the pattern I'm looking for with examples:

[EXAMPLE 1]
Input: [example input 1]
Output: [example output 1]

[EXAMPLE 2]
Input: [example input 2]
Output: [example output 2]

[EXAMPLE 3]
Input: [example input 3]
Output: [example output 3]

Now apply this exact pattern to:
{prompt}""",
            "suffix": ""
        },
        "role_expert": {
            "name": "Expert Role Assignment",
            "description": "Assigns a specific expert persona with credentials",
            "best_for": ["Technical questions", "Professional advice", "Domain expertise"],
            "template": """You are a world-class expert in this field with the following credentials:
- 20+ years of hands-on experience
- Published author and thought leader
- Consultant to Fortune 500 companies
- PhD-level knowledge in the domain

Drawing on your deep expertise and experience:

{prompt}

Provide insights that only a true expert would know, including:
- Common pitfalls to avoid
- Best practices from real-world experience
- Nuanced considerations often overlooked""",
            "suffix": ""
        },
        "structured_output": {
            "name": "Structured Output",
            "description": "Requests response in a specific organized format",
            "best_for": ["Reports", "Documentation", "Consistent formatting"],
            "template": """{prompt}

Please structure your response using this exact format:

## Executive Summary
[2-3 sentence overview]

## Key Points
- Point 1
- Point 2
- Point 3

## Detailed Analysis
[Comprehensive explanation]

## Recommendations
1. [First recommendation]
2. [Second recommendation]
3. [Third recommendation]

## Conclusion
[Final thoughts and next steps]""",
            "suffix": ""
        },
        "constraint_based": {
            "name": "Constraint-Based",
            "description": "Applies specific limitations to focus the response",
            "best_for": ["Concise responses", "Specific requirements", "Focused output"],
            "template": """{prompt}

CONSTRAINTS:
- Maximum length: 500 words
- Reading level: Accessible to general audience
- Tone: Professional yet approachable
- Format: Use bullet points for lists
- Include: At least 2 practical examples
- Exclude: Jargon without definitions
- Citations: Note any assumptions made""",
            "suffix": ""
        },
        "socratic": {
            "name": "Socratic Method",
            "description": "Uses guided questions to explore topics deeply",
            "best_for": ["Learning", "Deep understanding", "Critical thinking"],
            "template": """Let's explore this topic through the Socratic method:

{prompt}

Guide your response by addressing these questions:

1. DEFINITION: What exactly are we discussing? Define key terms.
2. ASSUMPTIONS: What underlying assumptions exist?
3. EVIDENCE: What evidence supports different viewpoints?
4. IMPLICATIONS: What are the consequences of each position?
5. ALTERNATIVES: What other perspectives should be considered?
6. SYNTHESIS: How do these elements combine into understanding?

Build understanding progressively through each question.""",
            "suffix": ""
        },
        "tree_of_thought": {
            "name": "Tree of Thoughts (ToT)",
            "description": "Explores multiple reasoning paths before converging",
            "best_for": ["Complex decisions", "Creative solutions", "Strategy"],
            "template": """{prompt}

Use the Tree of Thoughts approach:

BRANCH 1 - Conservative Approach:
[Develop this path fully]

BRANCH 2 - Innovative Approach:
[Develop this path fully]

BRANCH 3 - Hybrid Approach:
[Develop this path fully]

EVALUATION:
For each branch, assess:
- Feasibility (1-10)
- Risk level (1-10)
- Potential impact (1-10)
- Resource requirements

CONVERGENCE:
Based on evaluation, recommend the optimal path with justification.""",
            "suffix": ""
        },
        "multi_persona": {
            "name": "Multi-Persona Analysis",
            "description": "Analyzes from multiple stakeholder perspectives",
            "best_for": ["Decision making", "Stakeholder analysis", "Comprehensive review"],
            "template": """{prompt}

Analyze this from multiple perspectives:

THE OPTIMIST:
What's the best possible outcome? What opportunities exist?

THE SKEPTIC:
What could go wrong? What are the risks and weaknesses?

THE PRAGMATIST:
What's the realistic assessment? What's achievable?

THE INNOVATOR:
What unconventional approaches might work? What's being overlooked?

THE END USER:
How would this actually be experienced? What matters most?

SYNTHESIS:
Combine insights from all perspectives into actionable recommendations.""",
            "suffix": ""
        },
        "metacognitive": {
            "name": "Metacognitive Prompting",
            "description": "Encourages self-reflection and uncertainty acknowledgment",
            "best_for": ["Research", "Complex topics", "Honest assessment"],
            "template": """{prompt}

As you respond, apply metacognitive awareness:

KNOWLEDGE ASSESSMENT:
- What do I know with high confidence?
- What am I less certain about?
- What am I assuming without evidence?

REASONING CHECK:
- Is my logic sound?
- Are there gaps in my reasoning?
- What alternative conclusions are possible?

CONFIDENCE LEVELS:
Rate each major claim (High/Medium/Low confidence)

LIMITATIONS:
Explicitly note what's outside the scope of this response

FINAL ANSWER:
[Your response with embedded confidence indicators]""",
            "suffix": ""
        },
        "decomposition": {
            "name": "Task Decomposition",
            "description": "Breaks complex tasks into manageable subtasks",
            "best_for": ["Complex projects", "Planning", "Problem solving"],
            "template": """Complex Task: {prompt}

DECOMPOSITION:

PHASE 1 - ANALYSIS
Subtask 1.1: [Define scope and boundaries]
Subtask 1.2: [Identify key components]
Subtask 1.3: [Map dependencies]

PHASE 2 - PLANNING
Subtask 2.1: [Determine approach for each component]
Subtask 2.2: [Sequence tasks optimally]
Subtask 2.3: [Identify resources needed]

PHASE 3 - EXECUTION
Subtask 3.1: [Execute core components]
Subtask 3.2: [Integrate results]
Subtask 3.3: [Validate output]

PHASE 4 - VERIFICATION
Subtask 4.1: [Check completeness]
Subtask 4.2: [Verify quality]
Subtask 4.3: [Document learnings]

Execute each phase sequentially, providing output for each subtask.""",
            "suffix": ""
        },
        "contrarian": {
            "name": "Contrarian Challenge",
            "description": "Deliberately challenges assumptions and conventional wisdom",
            "best_for": ["Innovation", "Critical analysis", "Avoiding groupthink"],
            "template": """{prompt}

Apply contrarian thinking:

CONVENTIONAL WISDOM:
What's the standard/expected answer to this?

CHALLENGE ASSUMPTIONS:
List 5 assumptions embedded in the conventional view

CONTRARIAN PERSPECTIVES:
For each assumption, argue the opposite position

EVIDENCE HUNT:
What evidence supports the contrarian views?

SYNTHESIS:
What insights emerge from challenging the norm?

REVISED POSITION:
Formulate an improved answer incorporating contrarian insights""",
            "suffix": ""
        },
        "first_principles": {
            "name": "First Principles Reasoning",
            "description": "Builds understanding from fundamental truths",
            "best_for": ["Innovation", "Deep understanding", "Novel solutions"],
            "template": """{prompt}

Apply first principles thinking:

STEP 1 - IDENTIFY FUNDAMENTALS
What are the absolute basic truths about this topic?
Strip away all assumptions and conventions.

STEP 2 - QUESTION EVERYTHING
Why do we do it this way?
Is that reason still valid?
What if we started from scratch?

STEP 3 - BUILD FROM SCRATCH
Given only the fundamentals, how would we solve this?
What's the most logical approach without legacy constraints?

STEP 4 - COMPARE AND CONTRAST
How does the first-principles solution differ from current approaches?
What can we learn from the difference?

STEP 5 - ACTIONABLE INSIGHTS
What specific changes does this analysis suggest?""",
            "suffix": ""
        }
    }

    TASK_CATEGORIES = {
        "coding": {
            "name": "Software Development",
            "icon": "code",
            "system_prompt": "You are a senior software engineer with expertise in clean code, design patterns, security best practices, and performance optimization.",
            "enhancements": [
                "Include comprehensive error handling",
                "Add inline documentation and docstrings",
                "Follow language-specific conventions and style guides",
                "Consider edge cases and input validation",
                "Include example usage and test cases",
                "Address security considerations",
                "Optimize for readability and maintainability"
            ],
            "recommended_techniques": ["chain_of_thought", "decomposition", "structured_output"]
        },
        "writing": {
            "name": "Content Writing",
            "icon": "write",
            "system_prompt": "You are an expert content writer with a talent for engaging, clear, and persuasive writing across multiple formats and audiences.",
            "enhancements": [
                "Define target audience clearly",
                "Specify desired tone and voice",
                "Include SEO considerations if applicable",
                "Request specific length and format",
                "Ask for compelling hooks and conclusions",
                "Include calls-to-action where relevant"
            ],
            "recommended_techniques": ["role_expert", "structured_output", "constraint_based"]
        },
        "analysis": {
            "name": "Data Analysis",
            "icon": "chart",
            "system_prompt": "You are a data analyst with expertise in statistical analysis, data visualization, and extracting actionable insights from complex datasets.",
            "enhancements": [
                "Specify analysis methodology",
                "Request data visualizations descriptions",
                "Include statistical significance considerations",
                "Ask for confidence intervals where applicable",
                "Request actionable recommendations",
                "Include limitations and caveats"
            ],
            "recommended_techniques": ["metacognitive", "chain_of_thought", "structured_output"]
        },
        "creative": {
            "name": "Creative & Design",
            "icon": "art",
            "system_prompt": "You are a creative professional with expertise in innovative thinking, design principles, and generating unique ideas that resonate with audiences.",
            "enhancements": [
                "Encourage unconventional approaches",
                "Request multiple variations",
                "Include mood/atmosphere/tone details",
                "Specify creative constraints for focus",
                "Ask for rationale behind creative choices",
                "Include inspiration sources"
            ],
            "recommended_techniques": ["tree_of_thought", "contrarian", "multi_persona"]
        },
        "research": {
            "name": "Research & Information",
            "icon": "search",
            "system_prompt": "You are a research specialist skilled at synthesizing information, evaluating sources, and presenting balanced, well-supported analysis.",
            "enhancements": [
                "Request source citations",
                "Ask for multiple perspectives",
                "Include methodology description",
                "Request confidence levels for claims",
                "Include limitations and gaps",
                "Ask for future research directions"
            ],
            "recommended_techniques": ["metacognitive", "socratic", "first_principles"]
        },
        "strategy": {
            "name": "Business & Strategy",
            "icon": "strategy",
            "system_prompt": "You are a strategic consultant with expertise in business analysis, market dynamics, and organizational development.",
            "enhancements": [
                "Include market context",
                "Request SWOT analysis",
                "Add competitive landscape",
                "Include financial considerations",
                "Request risk assessment",
                "Provide implementation roadmap"
            ],
            "recommended_techniques": ["tree_of_thought", "multi_persona", "decomposition"]
        },
        "education": {
            "name": "Education & Training",
            "icon": "book",
            "system_prompt": "You are an experienced educator skilled at explaining complex concepts in accessible ways and creating effective learning experiences.",
            "enhancements": [
                "Specify learner level clearly",
                "Include analogies and examples",
                "Add practice exercises",
                "Request comprehension checks",
                "Include common misconceptions",
                "Provide additional resources"
            ],
            "recommended_techniques": ["socratic", "decomposition", "few_shot"]
        },
        "technical": {
            "name": "Technical Documentation",
            "icon": "docs",
            "system_prompt": "You are a technical writer with expertise in creating clear, comprehensive documentation that serves both novice and expert users.",
            "enhancements": [
                "Include quick-start guide",
                "Add detailed reference section",
                "Include troubleshooting guide",
                "Request code examples",
                "Add version/compatibility notes",
                "Include glossary of terms"
            ],
            "recommended_techniques": ["structured_output", "decomposition", "few_shot"]
        }
    }


class PromptOptimizer:
    """Local prompt optimization engine."""

    @staticmethod
    def optimize(prompt: str, technique: str, category: str, custom_instructions: str = "") -> str:
        """Optimize prompt using selected technique and category."""
        tech = PromptEngineeringTechniques.TECHNIQUES.get(technique, {})
        cat = PromptEngineeringTechniques.TASK_CATEGORIES.get(category, {})

        parts = []

        # Add system context
        if cat.get('system_prompt'):
            parts.append(f"[ROLE]\n{cat['system_prompt']}\n")

        # Apply technique template
        if tech.get('template'):
            optimized_prompt = tech['template'].format(prompt=prompt)
        else:
            optimized_prompt = prompt

        parts.append(f"[OPTIMIZED PROMPT]\n{optimized_prompt}")

        # Add category-specific enhancements
        if cat.get('enhancements'):
            parts.append("\n[QUALITY REQUIREMENTS]")
            for i, enhancement in enumerate(cat['enhancements'], 1):
                parts.append(f"{i}. {enhancement}")

        # Add custom instructions if provided
        if custom_instructions.strip():
            parts.append(f"\n[ADDITIONAL INSTRUCTIONS]\n{custom_instructions}")

        # Add output format
        parts.append("\n[OUTPUT GUIDELINES]")
        parts.append("- Provide a comprehensive, well-structured response")
        parts.append("- Address all aspects of the prompt")
        parts.append("- Be specific and actionable")

        # Add technique suffix if applicable
        if tech.get('suffix'):
            parts.append(tech['suffix'])

        return "\n".join(parts)

    @staticmethod
    def quick_enhance(prompt: str) -> str:
        """Apply quick enhancements to improve prompt."""
        enhanced = prompt.strip()

        # Ensure proper punctuation
        if enhanced and not enhanced[-1] in '.?!':
            enhanced += '.'

        # Add structure if prompt is long but lacks it
        if '\n' not in enhanced and len(enhanced) > 300:
            sentences = re.split(r'(?<=[.!?])\s+', enhanced)
            if len(sentences) > 3:
                enhanced = '\n\n'.join(sentences)

        # Add output specification if missing
        output_keywords = ['output', 'format', 'return', 'provide', 'respond', 'give me']
        if not any(kw in enhanced.lower() for kw in output_keywords):
            enhanced += "\n\nPlease provide a clear, well-organized response."

        return enhanced


class APIProvider:
    """Base class for AI API providers."""

    def __init__(self, name: str, api_key: str = ""):
        self.name = name
        self.api_key = api_key

    def optimize(self, prompt: str, system_prompt: str = "") -> Optional[str]:
        raise NotImplementedError


class OpenAIProvider(APIProvider):
    """OpenAI API provider."""

    def __init__(self, api_key: str = ""):
        super().__init__("OpenAI", api_key)
        self.base_url = "https://api.openai.com/v1"

    def optimize(self, prompt: str, system_prompt: str = "") -> Optional[str]:
        if not self.api_key or not HAS_REQUESTS:
            return None

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
            "max_tokens": 4000,
            "temperature": 0.7
        }

        try:
            response = requests.post(
                f"{self.base_url}/chat/completions",
                headers=headers,
                json=payload,
                timeout=120
            )

            if response.status_code == 200:
                data = response.json()
                if 'choices' in data and data['choices']:
                    return data['choices'][0].get('message', {}).get('content', '')
        except Exception as e:
            print(f"OpenAI API error: {e}")

        return None


class AnthropicProvider(APIProvider):
    """Anthropic Claude API provider."""

    def __init__(self, api_key: str = ""):
        super().__init__("Anthropic", api_key)
        self.base_url = "https://api.anthropic.com/v1"

    def optimize(self, prompt: str, system_prompt: str = "") -> Optional[str]:
        if not self.api_key or not HAS_REQUESTS:
            return None

        headers = {
            "x-api-key": self.api_key,
            "Content-Type": "application/json",
            "anthropic-version": "2023-06-01"
        }

        payload = {
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4000,
            "messages": [{"role": "user", "content": prompt}]
        }

        if system_prompt:
            payload["system"] = system_prompt

        try:
            response = requests.post(
                f"{self.base_url}/messages",
                headers=headers,
                json=payload,
                timeout=120
            )

            if response.status_code == 200:
                data = response.json()
                if 'content' in data and data['content']:
                    return data['content'][0].get('text', '')
        except Exception as e:
            print(f"Anthropic API error: {e}")

        return None


class QwenProvider(APIProvider):
    """Qwen API provider."""

    def __init__(self):
        super().__init__("Qwen", "")
        self.credentials = self._load_credentials()

    def _load_credentials(self) -> Optional[Dict]:
        paths = [
            Path.home() / ".qwen" / "oauth_creds.json",
            Path(os.environ.get("APPDATA", "")) / "qwen" / "oauth_creds.json",
            Path(os.environ.get("LOCALAPPDATA", "")) / "qwen" / "oauth_creds.json",
        ]

        for path in paths:
            if path.exists():
                try:
                    with open(path, 'r', encoding='utf-8') as f:
                        return json.load(f)
                except:
                    continue
        return None

    def optimize(self, prompt: str, system_prompt: str = "") -> Optional[str]:
        if not self.credentials or not HAS_REQUESTS:
            return None

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
            "max_tokens": 4000,
            "temperature": 0.7
        }

        try:
            response = requests.post(
                f"https://{resource_url}/v1/chat/completions",
                headers=headers,
                json=payload,
                timeout=120
            )

            if response.status_code == 200:
                data = response.json()
                if 'choices' in data and data['choices']:
                    return data['choices'][0].get('message', {}).get('content', '')
        except Exception as e:
            print(f"Qwen API error: {e}")

        return None


class HistoryManager:
    """Manages prompt history and favorites."""

    def __init__(self, storage_path: Path):
        self.storage_path = storage_path
        self.storage_path.mkdir(parents=True, exist_ok=True)
        self.history_file = storage_path / "history.json"
        self.favorites_file = storage_path / "favorites.json"
        self.templates_file = storage_path / "custom_templates.json"
        self.history: List[Dict] = []
        self.favorites: List[Dict] = []
        self.custom_templates: List[Dict] = []
        self.load()

    def load(self):
        """Load all data from disk."""
        for file_path, attr in [
            (self.history_file, 'history'),
            (self.favorites_file, 'favorites'),
            (self.templates_file, 'custom_templates')
        ]:
            try:
                if file_path.exists():
                    with open(file_path, 'r', encoding='utf-8') as f:
                        setattr(self, attr, json.load(f))
            except:
                setattr(self, attr, [])

    def save(self):
        """Save all data to disk."""
        try:
            with open(self.history_file, 'w', encoding='utf-8') as f:
                json.dump(self.history[-200:], f, indent=2)
            with open(self.favorites_file, 'w', encoding='utf-8') as f:
                json.dump(self.favorites, f, indent=2)
            with open(self.templates_file, 'w', encoding='utf-8') as f:
                json.dump(self.custom_templates, f, indent=2)
        except Exception as e:
            print(f"Error saving data: {e}")

    def add_to_history(self, original: str, optimized: str, technique: str,
                       category: str, analysis: Optional[PromptAnalysis] = None):
        """Add entry to history."""
        entry = {
            "id": hashlib.md5(f"{original}{time.time()}".encode()).hexdigest()[:12],
            "timestamp": datetime.now().isoformat(),
            "original": original,
            "optimized": optimized,
            "technique": technique,
            "category": category,
            "analysis": {
                "overall_score": analysis.overall_score if analysis else 0,
                "quality": analysis.quality.name if analysis else "UNKNOWN"
            } if analysis else None
        }
        self.history.append(entry)
        self.save()
        return entry

    def add_to_favorites(self, original: str, optimized: str, name: str = "", tags: List[str] = None):
        """Add entry to favorites."""
        entry = {
            "id": hashlib.md5(f"{original}{time.time()}".encode()).hexdigest()[:12],
            "timestamp": datetime.now().isoformat(),
            "name": name or f"Favorite {len(self.favorites) + 1}",
            "original": original,
            "optimized": optimized,
            "tags": tags or []
        }
        self.favorites.append(entry)
        self.save()
        return entry

    def remove_favorite(self, index: int):
        """Remove entry from favorites."""
        if 0 <= index < len(self.favorites):
            del self.favorites[index]
            self.save()

    def clear_history(self):
        """Clear all history."""
        self.history = []
        self.save()

    def search_history(self, query: str) -> List[Dict]:
        """Search through history."""
        query_lower = query.lower()
        return [
            entry for entry in self.history
            if query_lower in entry.get('original', '').lower() or
               query_lower in entry.get('optimized', '').lower()
        ]


class ModernScrolledText(tk.Frame):
    """Custom scrolled text widget with modern styling and enhanced features."""

    def __init__(self, parent, **kwargs):
        super().__init__(parent)

        # Extract custom options
        self.placeholder = kwargs.pop('placeholder', '')
        bg_color = kwargs.pop('bg', '#2d2d3d')
        fg_color = kwargs.pop('fg', '#cdd6f4')

        # Create text widget
        self.text = tk.Text(
            self,
            wrap=tk.WORD,
            font=kwargs.pop('font', ('Consolas', 11)),
            bg=bg_color,
            fg=fg_color,
            insertbackground=fg_color,
            selectbackground=kwargs.pop('selectbackground', '#89b4fa'),
            selectforeground=kwargs.pop('selectforeground', '#1e1e2e'),
            relief=tk.FLAT,
            padx=12,
            pady=12,
            undo=True,
            **kwargs
        )

        # Create scrollbar
        self.scrollbar = ttk.Scrollbar(self, orient=tk.VERTICAL, command=self.text.yview)
        self.text.configure(yscrollcommand=self.scrollbar.set)

        # Layout
        self.text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        # Placeholder handling
        if self.placeholder:
            self._show_placeholder()
            self.text.bind('<FocusIn>', self._on_focus_in)
            self.text.bind('<FocusOut>', self._on_focus_out)

    def _show_placeholder(self):
        """Show placeholder text."""
        self.text.insert('1.0', self.placeholder)
        self.text.config(fg='#6c6c8c')
        self.showing_placeholder = True

    def _on_focus_in(self, event):
        """Handle focus in - remove placeholder."""
        if hasattr(self, 'showing_placeholder') and self.showing_placeholder:
            self.text.delete('1.0', tk.END)
            self.text.config(fg='#cdd6f4')
            self.showing_placeholder = False

    def _on_focus_out(self, event):
        """Handle focus out - show placeholder if empty."""
        if not self.text.get('1.0', tk.END).strip():
            self._show_placeholder()

    def get(self, *args):
        """Get text content."""
        content = self.text.get(*args)
        if hasattr(self, 'showing_placeholder') and self.showing_placeholder:
            return ''
        return content

    def insert(self, *args):
        """Insert text."""
        if hasattr(self, 'showing_placeholder') and self.showing_placeholder:
            self.text.delete('1.0', tk.END)
            self.text.config(fg='#cdd6f4')
            self.showing_placeholder = False
        self.text.insert(*args)

    def delete(self, *args):
        """Delete text."""
        self.text.delete(*args)

    def bind(self, *args):
        """Bind event."""
        self.text.bind(*args)

    def config(self, **kwargs):
        """Configure text widget."""
        self.text.config(**kwargs)

    def focus_set(self):
        """Set focus to text widget."""
        self.text.focus_set()


class PromptEngineerUltimate:
    """Main application class."""

    VERSION = "2.0.0"
    APP_NAME = "Prompt Engineer Ultimate"

    def __init__(self):
        self.root = tk.Tk()
        self.root.title(f"{self.APP_NAME} v{self.VERSION}")
        self.root.geometry("1600x1000")
        self.root.minsize(1200, 800)

        # Color theme
        self.colors = {
            'bg': '#1e1e2e',
            'bg_secondary': '#2d2d3d',
            'bg_tertiary': '#3d3d4d',
            'bg_highlight': '#45475a',
            'text': '#cdd6f4',
            'text_secondary': '#a6adc8',
            'text_muted': '#6c6c8c',
            'accent': '#89b4fa',
            'accent_hover': '#b4befe',
            'success': '#a6e3a1',
            'warning': '#f9e2af',
            'error': '#f38ba8',
            'border': '#45475a',
            'score_excellent': '#a6e3a1',
            'score_good': '#94e2d5',
            'score_fair': '#f9e2af',
            'score_poor': '#f38ba8'
        }

        # Apply theme
        self.root.configure(bg=self.colors['bg'])
        self.style = ttk.Style()
        self.style.theme_use('clam')
        self._configure_styles()

        # Initialize storage
        self.storage_path = Path.home() / ".prompt_engineer_ultimate"
        self.history_manager = HistoryManager(self.storage_path)
        self.settings = self._load_settings()

        # Initialize providers
        self.providers = {
            'local': None,
            'qwen': QwenProvider(),
            'openai': OpenAIProvider(self.settings.get('openai_api_key', '')),
            'anthropic': AnthropicProvider(self.settings.get('anthropic_api_key', ''))
        }

        # State variables
        self.current_technique = tk.StringVar(value='chain_of_thought')
        self.current_category = tk.StringVar(value='coding')
        self.current_provider = tk.StringVar(value='local')
        self.auto_copy = tk.BooleanVar(value=self.settings.get('auto_copy', True))
        self.auto_analyze = tk.BooleanVar(value=self.settings.get('auto_analyze', True))
        self.current_analysis: Optional[PromptAnalysis] = None

        # Build UI
        self._build_ui()
        self._bind_shortcuts()

        # Initial state
        self._on_technique_change()

    def _configure_styles(self):
        """Configure ttk styles."""
        self.style.configure('.',
            background=self.colors['bg'],
            foreground=self.colors['text'],
            fieldbackground=self.colors['bg_secondary']
        )

        self.style.configure('TFrame', background=self.colors['bg'])
        self.style.configure('TLabel', background=self.colors['bg'], foreground=self.colors['text'])

        self.style.configure('TButton',
            background=self.colors['accent'],
            foreground=self.colors['bg'],
            padding=(20, 10),
            font=('Segoe UI', 10, 'bold')
        )
        self.style.map('TButton',
            background=[('active', self.colors['accent_hover']), ('disabled', self.colors['bg_tertiary'])],
            foreground=[('disabled', self.colors['text_muted'])]
        )

        self.style.configure('Secondary.TButton',
            background=self.colors['bg_tertiary'],
            foreground=self.colors['text'],
            padding=(12, 8)
        )
        self.style.map('Secondary.TButton',
            background=[('active', self.colors['border'])]
        )

        self.style.configure('Success.TButton',
            background=self.colors['success'],
            foreground=self.colors['bg'],
            padding=(15, 8)
        )

        self.style.configure('TCombobox',
            fieldbackground=self.colors['bg_secondary'],
            background=self.colors['bg_secondary'],
            foreground=self.colors['text'],
            padding=8
        )

        self.style.configure('TNotebook', background=self.colors['bg'])
        self.style.configure('TNotebook.Tab',
            background=self.colors['bg_secondary'],
            foreground=self.colors['text'],
            padding=(20, 10)
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
            background=self.colors['bg']
        )
        self.style.configure('TLabelframe.Label',
            background=self.colors['bg'],
            foreground=self.colors['accent'],
            font=('Segoe UI', 10, 'bold')
        )

        self.style.configure('Horizontal.TProgressbar',
            background=self.colors['accent'],
            troughcolor=self.colors['bg_secondary']
        )

    def _load_settings(self) -> Dict:
        """Load settings from file."""
        settings_file = self.storage_path / "settings.json"
        try:
            if settings_file.exists():
                with open(settings_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
        except:
            pass
        return {}

    def _save_settings(self):
        """Save settings to file."""
        settings_file = self.storage_path / "settings.json"
        self.storage_path.mkdir(parents=True, exist_ok=True)
        try:
            self.settings['auto_copy'] = self.auto_copy.get()
            self.settings['auto_analyze'] = self.auto_analyze.get()
            with open(settings_file, 'w', encoding='utf-8') as f:
                json.dump(self.settings, f, indent=2)
        except Exception as e:
            print(f"Error saving settings: {e}")

    def _build_ui(self):
        """Build the main UI."""
        # Main container
        main_container = ttk.Frame(self.root, padding=15)
        main_container.pack(fill=tk.BOTH, expand=True)

        # Header
        self._build_header(main_container)

        # Notebook for tabs
        self.notebook = ttk.Notebook(main_container)
        self.notebook.pack(fill=tk.BOTH, expand=True, pady=(15, 0))

        # Main optimization tab
        main_tab = ttk.Frame(self.notebook)
        self.notebook.add(main_tab, text="  Optimize  ")
        self._build_main_tab(main_tab)

        # Templates library tab
        templates_tab = ttk.Frame(self.notebook)
        self.notebook.add(templates_tab, text="  Templates  ")
        self._build_templates_tab(templates_tab)

        # Analysis tab
        analysis_tab = ttk.Frame(self.notebook)
        self.notebook.add(analysis_tab, text="  Analysis  ")
        self._build_analysis_tab(analysis_tab)

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
        """Build header section."""
        header = ttk.Frame(parent)
        header.pack(fill=tk.X, pady=(0, 10))

        # Title
        title = tk.Label(
            header,
            text=self.APP_NAME,
            font=('Segoe UI', 24, 'bold'),
            bg=self.colors['bg'],
            fg=self.colors['accent']
        )
        title.pack(side=tk.LEFT)

        # Subtitle
        subtitle = tk.Label(
            header,
            text="Create Perfect AI Prompts",
            font=('Segoe UI', 12),
            bg=self.colors['bg'],
            fg=self.colors['text_secondary']
        )
        subtitle.pack(side=tk.LEFT, padx=(20, 0), pady=(10, 0))

        # Quick stats
        stats_frame = ttk.Frame(header)
        stats_frame.pack(side=tk.RIGHT)

        self.stats_label = tk.Label(
            stats_frame,
            text=f"History: {len(self.history_manager.history)} | Favorites: {len(self.history_manager.favorites)}",
            font=('Segoe UI', 9),
            bg=self.colors['bg'],
            fg=self.colors['text_muted']
        )
        self.stats_label.pack()

    def _build_main_tab(self, parent):
        """Build main optimization tab."""
        # Horizontal paned window
        paned = ttk.PanedWindow(parent, orient=tk.HORIZONTAL)
        paned.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)

        # Left panel
        left_panel = ttk.Frame(paned)
        paned.add(left_panel, weight=1)

        # Options section
        self._build_options_section(left_panel)

        # Input section
        self._build_input_section(left_panel)

        # Right panel
        right_panel = ttk.Frame(paned)
        paned.add(right_panel, weight=1)

        # Output section
        self._build_output_section(right_panel)

        # Quick analysis panel (collapsible)
        self._build_quick_analysis(right_panel)

    def _build_options_section(self, parent):
        """Build options section."""
        options_frame = ttk.LabelFrame(parent, text="Optimization Settings", padding=12)
        options_frame.pack(fill=tk.X, pady=(0, 10))

        # Row 1: Provider and Category
        row1 = ttk.Frame(options_frame)
        row1.pack(fill=tk.X, pady=(0, 8))

        # Provider
        ttk.Label(row1, text="AI Provider:").pack(side=tk.LEFT)
        provider_combo = ttk.Combobox(
            row1,
            textvariable=self.current_provider,
            values=['local', 'qwen', 'openai', 'anthropic'],
            state='readonly',
            width=12
        )
        provider_combo.pack(side=tk.LEFT, padx=(8, 20))

        # Category
        ttk.Label(row1, text="Task Category:").pack(side=tk.LEFT)
        category_combo = ttk.Combobox(
            row1,
            textvariable=self.current_category,
            values=list(PromptEngineeringTechniques.TASK_CATEGORIES.keys()),
            state='readonly',
            width=15
        )
        category_combo.pack(side=tk.LEFT, padx=(8, 0))
        category_combo.bind('<<ComboboxSelected>>', self._on_category_change)

        # Row 2: Technique
        row2 = ttk.Frame(options_frame)
        row2.pack(fill=tk.X, pady=(0, 8))

        ttk.Label(row2, text="Technique:").pack(side=tk.LEFT)
        technique_combo = ttk.Combobox(
            row2,
            textvariable=self.current_technique,
            values=list(PromptEngineeringTechniques.TECHNIQUES.keys()),
            state='readonly',
            width=20
        )
        technique_combo.pack(side=tk.LEFT, padx=(8, 15))
        technique_combo.bind('<<ComboboxSelected>>', self._on_technique_change)

        # Technique description
        self.technique_desc = tk.Label(
            row2,
            text="",
            font=('Segoe UI', 9, 'italic'),
            bg=self.colors['bg'],
            fg=self.colors['text_secondary'],
            wraplength=400,
            anchor=tk.W
        )
        self.technique_desc.pack(side=tk.LEFT, fill=tk.X, expand=True)

        # Row 3: Checkboxes
        row3 = ttk.Frame(options_frame)
        row3.pack(fill=tk.X)

        ttk.Checkbutton(row3, text="Auto-copy result", variable=self.auto_copy).pack(side=tk.LEFT)
        ttk.Checkbutton(row3, text="Real-time analysis", variable=self.auto_analyze).pack(side=tk.LEFT, padx=(15, 0))

        # Recommended techniques label
        self.recommended_label = tk.Label(
            row3,
            text="",
            font=('Segoe UI', 8),
            bg=self.colors['bg'],
            fg=self.colors['text_muted']
        )
        self.recommended_label.pack(side=tk.RIGHT)

    def _build_input_section(self, parent):
        """Build input section."""
        input_frame = ttk.LabelFrame(parent, text="Your Prompt (Paste Large Text Here)", padding=10)
        input_frame.pack(fill=tk.BOTH, expand=True)

        # Text area
        self.input_text = ModernScrolledText(
            input_frame,
            font=('Consolas', 11),
            bg=self.colors['bg_secondary'],
            fg=self.colors['text'],
            placeholder="Paste or type your prompt here...\n\nSupports large text blocks - just paste and optimize!"
        )
        self.input_text.pack(fill=tk.BOTH, expand=True)

        # Bind for real-time analysis
        self.input_text.bind('<KeyRelease>', self._on_input_change)

        # Toolbar
        toolbar = ttk.Frame(input_frame)
        toolbar.pack(fill=tk.X, pady=(10, 0))

        ttk.Button(toolbar, text="Paste", style='Secondary.TButton',
                  command=self._paste_input).pack(side=tk.LEFT)
        ttk.Button(toolbar, text="Clear", style='Secondary.TButton',
                  command=self._clear_input).pack(side=tk.LEFT, padx=(5, 0))
        ttk.Button(toolbar, text="Load File", style='Secondary.TButton',
                  command=self._load_file).pack(side=tk.LEFT, padx=(5, 0))
        ttk.Button(toolbar, text="Analyze", style='Secondary.TButton',
                  command=self._analyze_input).pack(side=tk.LEFT, padx=(5, 0))

        # Character count
        self.input_stats = tk.Label(
            toolbar,
            text="0 chars | 0 words",
            font=('Segoe UI', 9),
            bg=self.colors['bg'],
            fg=self.colors['text_muted']
        )
        self.input_stats.pack(side=tk.RIGHT)

        # Action buttons
        action_frame = ttk.Frame(input_frame)
        action_frame.pack(fill=tk.X, pady=(10, 0))

        self.optimize_btn = ttk.Button(
            action_frame,
            text="Optimize Prompt",
            command=self._optimize_prompt
        )
        self.optimize_btn.pack(side=tk.LEFT)

        ttk.Button(
            action_frame,
            text="Quick Enhance",
            style='Secondary.TButton',
            command=self._quick_enhance
        ).pack(side=tk.LEFT, padx=(10, 0))

        # Score indicator
        self.score_frame = ttk.Frame(action_frame)
        self.score_frame.pack(side=tk.RIGHT)

        self.score_label = tk.Label(
            self.score_frame,
            text="Score: --",
            font=('Segoe UI', 11, 'bold'),
            bg=self.colors['bg'],
            fg=self.colors['text_muted']
        )
        self.score_label.pack(side=tk.LEFT)

    def _build_output_section(self, parent):
        """Build output section."""
        output_frame = ttk.LabelFrame(parent, text="Optimized Prompt", padding=10)
        output_frame.pack(fill=tk.BOTH, expand=True)

        # Text area
        self.output_text = ModernScrolledText(
            output_frame,
            font=('Consolas', 11),
            bg=self.colors['bg_secondary'],
            fg=self.colors['success']
        )
        self.output_text.pack(fill=tk.BOTH, expand=True)

        # Toolbar
        toolbar = ttk.Frame(output_frame)
        toolbar.pack(fill=tk.X, pady=(10, 0))

        ttk.Button(toolbar, text="Copy", style='Success.TButton',
                  command=self._copy_output).pack(side=tk.LEFT)
        ttk.Button(toolbar, text="Save", style='Secondary.TButton',
                  command=self._save_output).pack(side=tk.LEFT, padx=(5, 0))
        ttk.Button(toolbar, text="Add to Favorites", style='Secondary.TButton',
                  command=self._add_favorite).pack(side=tk.LEFT, padx=(5, 0))
        ttk.Button(toolbar, text="Use as Input", style='Secondary.TButton',
                  command=self._use_as_input).pack(side=tk.LEFT, padx=(5, 0))

        # Output stats
        self.output_stats = tk.Label(
            toolbar,
            text="0 chars | 0 words",
            font=('Segoe UI', 9),
            bg=self.colors['bg'],
            fg=self.colors['text_muted']
        )
        self.output_stats.pack(side=tk.RIGHT)

    def _build_quick_analysis(self, parent):
        """Build quick analysis panel."""
        analysis_frame = ttk.LabelFrame(parent, text="Quick Analysis", padding=10)
        analysis_frame.pack(fill=tk.X, pady=(10, 0))

        # Score bars
        self.score_bars = {}
        metrics = [
            ('clarity', 'Clarity'),
            ('specificity', 'Specificity'),
            ('structure', 'Structure'),
            ('actionability', 'Actionability'),
            ('context', 'Context')
        ]

        for metric_id, metric_name in metrics:
            row = ttk.Frame(analysis_frame)
            row.pack(fill=tk.X, pady=2)

            ttk.Label(row, text=f"{metric_name}:", width=12).pack(side=tk.LEFT)

            progress = ttk.Progressbar(row, length=150, mode='determinate')
            progress.pack(side=tk.LEFT, padx=(5, 10))

            score_label = tk.Label(
                row,
                text="--",
                font=('Segoe UI', 9),
                bg=self.colors['bg'],
                fg=self.colors['text_muted'],
                width=4
            )
            score_label.pack(side=tk.LEFT)

            self.score_bars[metric_id] = (progress, score_label)

        # Issues/suggestions summary
        self.analysis_summary = tk.Label(
            analysis_frame,
            text="Enter a prompt to see analysis",
            font=('Segoe UI', 9),
            bg=self.colors['bg'],
            fg=self.colors['text_muted'],
            wraplength=350,
            justify=tk.LEFT
        )
        self.analysis_summary.pack(fill=tk.X, pady=(10, 0))

    def _build_templates_tab(self, parent):
        """Build templates tab."""
        # Left: Categories list
        left_frame = ttk.Frame(parent)
        left_frame.pack(side=tk.LEFT, fill=tk.Y, padx=10, pady=10)

        ttk.Label(left_frame, text="Categories", font=('Segoe UI', 12, 'bold')).pack(anchor=tk.W)

        self.category_list = tk.Listbox(
            left_frame,
            font=('Segoe UI', 10),
            bg=self.colors['bg_secondary'],
            fg=self.colors['text'],
            selectbackground=self.colors['accent'],
            selectforeground=self.colors['bg'],
            relief=tk.FLAT,
            width=25,
            height=10
        )
        self.category_list.pack(fill=tk.Y, expand=True, pady=(10, 0))

        for cat_id, cat_info in PromptEngineeringTechniques.TASK_CATEGORIES.items():
            self.category_list.insert(tk.END, f"  {cat_info['name']}")

        self.category_list.bind('<<ListboxSelect>>', self._on_template_category_select)

        ttk.Label(left_frame, text="\nTechniques", font=('Segoe UI', 12, 'bold')).pack(anchor=tk.W)

        self.technique_list = tk.Listbox(
            left_frame,
            font=('Segoe UI', 10),
            bg=self.colors['bg_secondary'],
            fg=self.colors['text'],
            selectbackground=self.colors['accent'],
            selectforeground=self.colors['bg'],
            relief=tk.FLAT,
            width=25,
            height=12
        )
        self.technique_list.pack(fill=tk.Y, expand=True, pady=(10, 0))

        for tech_id, tech_info in PromptEngineeringTechniques.TECHNIQUES.items():
            self.technique_list.insert(tk.END, f"  {tech_info['name']}")

        self.technique_list.bind('<<ListboxSelect>>', self._on_template_technique_select)

        # Right: Template details
        right_frame = ttk.Frame(parent)
        right_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=10, pady=10)

        ttk.Label(right_frame, text="Template Details", font=('Segoe UI', 12, 'bold')).pack(anchor=tk.W)

        self.template_details = ModernScrolledText(
            right_frame,
            font=('Consolas', 10),
            bg=self.colors['bg_secondary'],
            fg=self.colors['text'],
            height=25
        )
        self.template_details.pack(fill=tk.BOTH, expand=True, pady=(10, 0))

        # Buttons
        btn_frame = ttk.Frame(right_frame)
        btn_frame.pack(fill=tk.X, pady=(10, 0))

        ttk.Button(btn_frame, text="Use This Template",
                  command=self._use_selected_template).pack(side=tk.LEFT)
        ttk.Button(btn_frame, text="Copy Template", style='Secondary.TButton',
                  command=self._copy_template).pack(side=tk.LEFT, padx=(10, 0))

    def _build_analysis_tab(self, parent):
        """Build detailed analysis tab."""
        # Analysis input
        input_frame = ttk.LabelFrame(parent, text="Prompt to Analyze", padding=10)
        input_frame.pack(fill=tk.X, padx=10, pady=10)

        self.analysis_input = ModernScrolledText(
            input_frame,
            font=('Consolas', 10),
            bg=self.colors['bg_secondary'],
            fg=self.colors['text'],
            height=8
        )
        self.analysis_input.pack(fill=tk.X)

        btn_frame = ttk.Frame(input_frame)
        btn_frame.pack(fill=tk.X, pady=(10, 0))

        ttk.Button(btn_frame, text="Analyze Prompt",
                  command=self._perform_detailed_analysis).pack(side=tk.LEFT)
        ttk.Button(btn_frame, text="Use Main Input", style='Secondary.TButton',
                  command=self._copy_main_to_analysis).pack(side=tk.LEFT, padx=(10, 0))

        # Results
        results_frame = ttk.LabelFrame(parent, text="Analysis Results", padding=10)
        results_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=(0, 10))

        self.analysis_results = ModernScrolledText(
            results_frame,
            font=('Consolas', 10),
            bg=self.colors['bg_secondary'],
            fg=self.colors['text']
        )
        self.analysis_results.pack(fill=tk.BOTH, expand=True)

    def _build_history_tab(self, parent):
        """Build history tab."""
        # Sub-notebook for history/favorites
        sub_notebook = ttk.Notebook(parent)
        sub_notebook.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

        # Recent history
        history_frame = ttk.Frame(sub_notebook)
        sub_notebook.add(history_frame, text="  Recent  ")

        self.history_list = tk.Listbox(
            history_frame,
            font=('Segoe UI', 10),
            bg=self.colors['bg_secondary'],
            fg=self.colors['text'],
            selectbackground=self.colors['accent'],
            selectforeground=self.colors['bg'],
            relief=tk.FLAT
        )
        self.history_list.pack(fill=tk.BOTH, expand=True, pady=10)
        self.history_list.bind('<<ListboxSelect>>', self._on_history_select)
        self.history_list.bind('<Double-1>', self._load_from_history)

        history_btn_frame = ttk.Frame(history_frame)
        history_btn_frame.pack(fill=tk.X)

        ttk.Button(history_btn_frame, text="Load Selected",
                  command=self._load_from_history).pack(side=tk.LEFT)
        ttk.Button(history_btn_frame, text="Add to Favorites", style='Secondary.TButton',
                  command=self._history_to_favorites).pack(side=tk.LEFT, padx=(10, 0))
        ttk.Button(history_btn_frame, text="Clear History", style='Secondary.TButton',
                  command=self._clear_history).pack(side=tk.RIGHT)

        # Favorites
        favorites_frame = ttk.Frame(sub_notebook)
        sub_notebook.add(favorites_frame, text="  Favorites  ")

        self.favorites_list = tk.Listbox(
            favorites_frame,
            font=('Segoe UI', 10),
            bg=self.colors['bg_secondary'],
            fg=self.colors['text'],
            selectbackground=self.colors['accent'],
            selectforeground=self.colors['bg'],
            relief=tk.FLAT
        )
        self.favorites_list.pack(fill=tk.BOTH, expand=True, pady=10)
        self.favorites_list.bind('<Double-1>', self._load_from_favorites)

        favorites_btn_frame = ttk.Frame(favorites_frame)
        favorites_btn_frame.pack(fill=tk.X)

        ttk.Button(favorites_btn_frame, text="Load Selected",
                  command=self._load_from_favorites).pack(side=tk.LEFT)
        ttk.Button(favorites_btn_frame, text="Remove", style='Secondary.TButton',
                  command=self._remove_favorite).pack(side=tk.LEFT, padx=(10, 0))

        # Refresh lists
        self._refresh_history_lists()

    def _build_settings_tab(self, parent):
        """Build settings tab."""
        settings_container = ttk.Frame(parent, padding=20)
        settings_container.pack(fill=tk.BOTH, expand=True)

        # API Keys
        api_frame = ttk.LabelFrame(settings_container, text="API Keys", padding=15)
        api_frame.pack(fill=tk.X, pady=(0, 15))

        # OpenAI
        openai_row = ttk.Frame(api_frame)
        openai_row.pack(fill=tk.X, pady=(0, 10))
        ttk.Label(openai_row, text="OpenAI API Key:", width=18).pack(side=tk.LEFT)
        self.openai_key = ttk.Entry(openai_row, width=50, show="*")
        self.openai_key.pack(side=tk.LEFT, padx=(10, 0))
        self.openai_key.insert(0, self.settings.get('openai_api_key', ''))

        # Anthropic
        anthropic_row = ttk.Frame(api_frame)
        anthropic_row.pack(fill=tk.X, pady=(0, 10))
        ttk.Label(anthropic_row, text="Anthropic API Key:", width=18).pack(side=tk.LEFT)
        self.anthropic_key = ttk.Entry(anthropic_row, width=50, show="*")
        self.anthropic_key.pack(side=tk.LEFT, padx=(10, 0))
        self.anthropic_key.insert(0, self.settings.get('anthropic_api_key', ''))

        # Qwen status
        qwen_row = ttk.Frame(api_frame)
        qwen_row.pack(fill=tk.X)
        ttk.Label(qwen_row, text="Qwen Credentials:", width=18).pack(side=tk.LEFT)
        qwen_status = "Configured" if self.providers['qwen'].credentials else "Not found"
        qwen_color = self.colors['success'] if self.providers['qwen'].credentials else self.colors['error']
        tk.Label(qwen_row, text=qwen_status, font=('Segoe UI', 10), bg=self.colors['bg'], fg=qwen_color).pack(side=tk.LEFT, padx=(10, 0))

        # Preferences
        prefs_frame = ttk.LabelFrame(settings_container, text="Preferences", padding=15)
        prefs_frame.pack(fill=tk.X, pady=(0, 15))

        ttk.Checkbutton(prefs_frame, text="Auto-copy optimized prompt to clipboard", variable=self.auto_copy).pack(anchor=tk.W)
        ttk.Checkbutton(prefs_frame, text="Real-time prompt analysis", variable=self.auto_analyze).pack(anchor=tk.W, pady=(5, 0))

        # Save button
        save_frame = ttk.Frame(settings_container)
        save_frame.pack(fill=tk.X)

        ttk.Button(save_frame, text="Save Settings", command=self._save_api_settings).pack(side=tk.LEFT)

        self.settings_status = tk.Label(
            save_frame,
            text="",
            font=('Segoe UI', 10),
            bg=self.colors['bg'],
            fg=self.colors['success']
        )
        self.settings_status.pack(side=tk.LEFT, padx=(15, 0))

        # About section
        about_frame = ttk.LabelFrame(settings_container, text="About", padding=15)
        about_frame.pack(fill=tk.X, pady=(15, 0))

        tk.Label(
            about_frame,
            text=f"{self.APP_NAME} v{self.VERSION}",
            font=('Segoe UI', 11, 'bold'),
            bg=self.colors['bg'],
            fg=self.colors['text']
        ).pack(anchor=tk.W)

        tk.Label(
            about_frame,
            text="The ultimate prompt engineering tool for AI professionals.\nFeatures real-time analysis, multiple AI providers, and advanced optimization techniques.",
            font=('Segoe UI', 9),
            bg=self.colors['bg'],
            fg=self.colors['text_secondary'],
            justify=tk.LEFT
        ).pack(anchor=tk.W, pady=(5, 0))

    def _build_status_bar(self, parent):
        """Build status bar."""
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

        # Version
        tk.Label(
            status_frame,
            text=f"v{self.VERSION}",
            font=('Segoe UI', 9),
            bg=self.colors['bg'],
            fg=self.colors['text_muted']
        ).pack(side=tk.RIGHT)

    def _bind_shortcuts(self):
        """Bind keyboard shortcuts."""
        self.root.bind('<Control-Return>', lambda e: self._optimize_prompt())
        self.root.bind('<Control-v>', lambda e: self._paste_input())
        self.root.bind('<Control-c>', lambda e: self._copy_output())
        self.root.bind('<Control-s>', lambda e: self._save_output())
        self.root.bind('<F5>', lambda e: self._optimize_prompt())
        self.root.bind('<Control-a>', self._select_all)

    def _select_all(self, event):
        """Select all text in focused widget."""
        widget = event.widget
        if hasattr(widget, 'select_range'):
            widget.select_range(0, tk.END)
        elif hasattr(widget, 'tag_add'):
            widget.tag_add(tk.SEL, '1.0', tk.END)
        return 'break'

    def _on_technique_change(self, event=None):
        """Handle technique selection change."""
        tech_id = self.current_technique.get()
        tech = PromptEngineeringTechniques.TECHNIQUES.get(tech_id, {})
        self.technique_desc.config(text=tech.get('description', ''))

    def _on_category_change(self, event=None):
        """Handle category selection change."""
        cat_id = self.current_category.get()
        cat = PromptEngineeringTechniques.TASK_CATEGORIES.get(cat_id, {})
        recommended = cat.get('recommended_techniques', [])
        if recommended:
            self.recommended_label.config(text=f"Recommended: {', '.join(recommended)}")
        else:
            self.recommended_label.config(text="")

    def _on_input_change(self, event=None):
        """Handle input text change."""
        text = self.input_text.get('1.0', tk.END).strip()
        words = len(text.split()) if text else 0
        chars = len(text)
        self.input_stats.config(text=f"{chars} chars | {words} words")

        # Real-time analysis if enabled
        if self.auto_analyze.get() and text:
            self._update_quick_analysis(text)

    def _update_quick_analysis(self, text: str):
        """Update quick analysis display."""
        analysis = PromptAnalyzer.analyze(text)
        self.current_analysis = analysis

        # Update score bars
        scores = {
            'clarity': analysis.clarity_score,
            'specificity': analysis.specificity_score,
            'structure': analysis.structure_score,
            'actionability': analysis.actionability_score,
            'context': analysis.context_score
        }

        for metric_id, (progress, label) in self.score_bars.items():
            score = scores.get(metric_id, 0)
            progress['value'] = score
            label.config(text=f"{int(score)}")

            # Color based on score
            if score >= 75:
                label.config(fg=self.colors['score_excellent'])
            elif score >= 60:
                label.config(fg=self.colors['score_good'])
            elif score >= 40:
                label.config(fg=self.colors['score_fair'])
            else:
                label.config(fg=self.colors['score_poor'])

        # Update overall score
        if analysis.overall_score >= 75:
            score_color = self.colors['score_excellent']
        elif analysis.overall_score >= 60:
            score_color = self.colors['score_good']
        elif analysis.overall_score >= 40:
            score_color = self.colors['score_fair']
        else:
            score_color = self.colors['score_poor']

        self.score_label.config(
            text=f"Score: {int(analysis.overall_score)}/100 ({analysis.quality.name})",
            fg=score_color
        )

        # Update summary
        summary_parts = []
        if analysis.issues:
            summary_parts.append(f"Issues: {analysis.issues[0]}")
        if analysis.suggestions:
            summary_parts.append(f"Tip: {analysis.suggestions[0]}")

        if summary_parts:
            self.analysis_summary.config(text=" | ".join(summary_parts))
        else:
            self.analysis_summary.config(text="Good prompt structure detected!")

    def _paste_input(self, event=None):
        """Paste from clipboard."""
        try:
            if HAS_PYPERCLIP:
                text = pyperclip.paste()
            else:
                text = self.root.clipboard_get()
            self.input_text.delete('1.0', tk.END)
            self.input_text.insert('1.0', text)
            self._on_input_change()
            self._set_status("Pasted from clipboard")
        except Exception as e:
            self._set_status(f"Paste failed: {e}", error=True)
        return 'break'

    def _clear_input(self):
        """Clear input text."""
        self.input_text.delete('1.0', tk.END)
        self._on_input_change()
        self._set_status("Input cleared")

    def _load_file(self):
        """Load prompt from file."""
        file_path = filedialog.askopenfilename(
            filetypes=[("Text files", "*.txt"), ("Markdown", "*.md"), ("All files", "*.*")]
        )
        if file_path:
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                self.input_text.delete('1.0', tk.END)
                self.input_text.insert('1.0', content)
                self._on_input_change()
                self._set_status(f"Loaded: {Path(file_path).name}")
            except Exception as e:
                self._set_status(f"Load failed: {e}", error=True)

    def _analyze_input(self):
        """Analyze the input prompt."""
        text = self.input_text.get('1.0', tk.END).strip()
        if text:
            self._update_quick_analysis(text)
            self._set_status("Analysis complete")
        else:
            self._set_status("Enter a prompt to analyze", error=True)

    def _optimize_prompt(self):
        """Optimize the prompt."""
        text = self.input_text.get('1.0', tk.END).strip()
        if not text:
            self._set_status("Please enter a prompt to optimize", error=True)
            return

        self._set_status("Optimizing...")
        self.optimize_btn.config(state='disabled')

        def optimize_thread():
            try:
                provider_name = self.current_provider.get()
                technique = self.current_technique.get()
                category = self.current_category.get()

                tech_info = PromptEngineeringTechniques.TECHNIQUES.get(technique, {})
                cat_info = PromptEngineeringTechniques.TASK_CATEGORIES.get(category, {})

                result = None

                if provider_name == 'local':
                    result = PromptOptimizer.optimize(text, technique, category)
                else:
                    # Build meta-prompt for AI optimization
                    system_prompt = f"""You are an expert prompt engineer. Optimize the given prompt using the {tech_info.get('name', '')} technique for {cat_info.get('name', '')} tasks.

Your task is to transform the prompt to be maximally effective by:
1. Making it clear, specific, and actionable
2. Applying the {tech_info.get('name', '')} technique appropriately
3. Adding relevant context and constraints
4. Specifying the expected output format
5. Including examples if helpful

Return ONLY the optimized prompt, no explanations or meta-commentary."""

                    optimization_request = f"""Optimize this prompt using the {tech_info.get('name', '')} technique:

ORIGINAL PROMPT:
{text}

Apply {tech_info.get('description', '')} to create a significantly improved version."""

                    provider = self.providers.get(provider_name)
                    if provider:
                        result = provider.optimize(optimization_request, system_prompt)

                    if not result:
                        result = PromptOptimizer.optimize(text, technique, category)

                # Update UI
                self.root.after(0, lambda: self._display_result(result, text, technique, category))

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

        # Update output stats
        words = len(result.split()) if result else 0
        chars = len(result)
        self.output_stats.config(text=f"{chars} chars | {words} words")

        # Add to history
        self.history_manager.add_to_history(
            original, result, technique, category, self.current_analysis
        )
        self._refresh_history_lists()
        self._update_stats()

        # Auto-copy if enabled
        if self.auto_copy.get():
            self._copy_output()
            self._set_status("Optimized and copied to clipboard!")
        else:
            self._set_status("Optimization complete!")

    def _quick_enhance(self):
        """Quick enhancement without full optimization."""
        text = self.input_text.get('1.0', tk.END).strip()
        if not text:
            self._set_status("Enter a prompt to enhance", error=True)
            return

        enhanced = PromptOptimizer.quick_enhance(text)
        self.output_text.delete('1.0', tk.END)
        self.output_text.insert('1.0', enhanced)

        words = len(enhanced.split())
        chars = len(enhanced)
        self.output_stats.config(text=f"{chars} chars | {words} words")

        self._set_status("Quick enhancement applied")

    def _copy_output(self, event=None):
        """Copy output to clipboard."""
        text = self.output_text.get('1.0', tk.END).strip()
        if not text:
            self._set_status("Nothing to copy", error=True)
            return 'break'

        try:
            if HAS_PYPERCLIP:
                pyperclip.copy(text)
            else:
                self.root.clipboard_clear()
                self.root.clipboard_append(text)
            self._set_status("Copied to clipboard!")
        except Exception as e:
            self._set_status(f"Copy failed: {e}", error=True)
        return 'break'

    def _save_output(self, event=None):
        """Save output to file."""
        text = self.output_text.get('1.0', tk.END).strip()
        if not text:
            self._set_status("Nothing to save", error=True)
            return

        file_path = filedialog.asksaveasfilename(
            defaultextension=".txt",
            filetypes=[("Text files", "*.txt"), ("Markdown", "*.md"), ("All files", "*.*")]
        )
        if file_path:
            try:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(text)
                self._set_status(f"Saved: {Path(file_path).name}")
            except Exception as e:
                self._set_status(f"Save failed: {e}", error=True)

    def _add_favorite(self):
        """Add current prompt to favorites."""
        original = self.input_text.get('1.0', tk.END).strip()
        optimized = self.output_text.get('1.0', tk.END).strip()

        if not optimized:
            self._set_status("No optimized prompt to save", error=True)
            return

        self.history_manager.add_to_favorites(original, optimized)
        self._refresh_history_lists()
        self._update_stats()
        self._set_status("Added to favorites!")

    def _use_as_input(self):
        """Use output as new input."""
        text = self.output_text.get('1.0', tk.END).strip()
        if text:
            self.input_text.delete('1.0', tk.END)
            self.input_text.insert('1.0', text)
            self._on_input_change()
            self._set_status("Output moved to input")

    def _on_template_category_select(self, event=None):
        """Handle category selection in templates tab."""
        selection = self.category_list.curselection()
        if not selection:
            return

        cat_ids = list(PromptEngineeringTechniques.TASK_CATEGORIES.keys())
        cat_id = cat_ids[selection[0]]
        cat = PromptEngineeringTechniques.TASK_CATEGORIES[cat_id]

        details = f"CATEGORY: {cat['name']}\n{'=' * 50}\n\n"
        details += f"SYSTEM PROMPT:\n{cat['system_prompt']}\n\n"
        details += "ENHANCEMENTS:\n"
        for i, enh in enumerate(cat['enhancements'], 1):
            details += f"  {i}. {enh}\n"
        details += f"\nRECOMMENDED TECHNIQUES:\n  {', '.join(cat.get('recommended_techniques', []))}"

        self.template_details.delete('1.0', tk.END)
        self.template_details.insert('1.0', details)

    def _on_template_technique_select(self, event=None):
        """Handle technique selection in templates tab."""
        selection = self.technique_list.curselection()
        if not selection:
            return

        tech_ids = list(PromptEngineeringTechniques.TECHNIQUES.keys())
        tech_id = tech_ids[selection[0]]
        tech = PromptEngineeringTechniques.TECHNIQUES[tech_id]

        details = f"TECHNIQUE: {tech['name']}\n{'=' * 50}\n\n"
        details += f"DESCRIPTION:\n{tech['description']}\n\n"
        details += f"BEST FOR:\n  {', '.join(tech.get('best_for', []))}\n\n"
        details += f"TEMPLATE:\n{'-' * 40}\n{tech['template']}\n{'-' * 40}"
        if tech.get('suffix'):
            details += f"\n\nSUFFIX:\n{tech['suffix']}"

        self.template_details.delete('1.0', tk.END)
        self.template_details.insert('1.0', details)

    def _use_selected_template(self):
        """Use selected template in main tab."""
        # Check if category selected
        cat_selection = self.category_list.curselection()
        if cat_selection:
            cat_ids = list(PromptEngineeringTechniques.TASK_CATEGORIES.keys())
            self.current_category.set(cat_ids[cat_selection[0]])

        # Check if technique selected
        tech_selection = self.technique_list.curselection()
        if tech_selection:
            tech_ids = list(PromptEngineeringTechniques.TECHNIQUES.keys())
            self.current_technique.set(tech_ids[tech_selection[0]])

        self._on_technique_change()
        self._on_category_change()
        self.notebook.select(0)  # Switch to main tab
        self._set_status("Template applied - ready to optimize")

    def _copy_template(self):
        """Copy template details to clipboard."""
        text = self.template_details.get('1.0', tk.END).strip()
        if text:
            try:
                if HAS_PYPERCLIP:
                    pyperclip.copy(text)
                else:
                    self.root.clipboard_clear()
                    self.root.clipboard_append(text)
                self._set_status("Template copied!")
            except:
                pass

    def _perform_detailed_analysis(self):
        """Perform detailed prompt analysis."""
        text = self.analysis_input.get('1.0', tk.END).strip()
        if not text:
            self._set_status("Enter a prompt to analyze", error=True)
            return

        analysis = PromptAnalyzer.analyze(text)

        result = f"""PROMPT ANALYSIS REPORT
{'=' * 60}

OVERALL SCORE: {int(analysis.overall_score)}/100 ({analysis.quality.name})

METRICS:
  Clarity:       {int(analysis.clarity_score)}/100
  Specificity:   {int(analysis.specificity_score)}/100
  Structure:     {int(analysis.structure_score)}/100
  Actionability: {int(analysis.actionability_score)}/100
  Context:       {int(analysis.context_score)}/100

STATISTICS:
  Characters: {analysis.char_count}
  Words: {analysis.word_count}
  Sentences: {analysis.sentence_count}

COMPONENTS DETECTED:
  Clear Objective: {'Yes' if analysis.has_clear_objective else 'No'}
  Context/Background: {'Yes' if analysis.has_context else 'No'}
  Constraints: {'Yes' if analysis.has_constraints else 'No'}
  Output Format: {'Yes' if analysis.has_output_format else 'No'}
  Examples: {'Yes' if analysis.has_examples else 'No'}

ISSUES FOUND:
"""
        if analysis.issues:
            for issue in analysis.issues:
                result += f"  - {issue}\n"
        else:
            result += "  None detected\n"

        result += "\nSUGGESTIONS FOR IMPROVEMENT:\n"
        if analysis.suggestions:
            for suggestion in analysis.suggestions:
                result += f"  - {suggestion}\n"
        else:
            result += "  Your prompt is well-structured!\n"

        self.analysis_results.delete('1.0', tk.END)
        self.analysis_results.insert('1.0', result)
        self._set_status("Detailed analysis complete")

    def _copy_main_to_analysis(self):
        """Copy main input to analysis tab."""
        text = self.input_text.get('1.0', tk.END).strip()
        if text:
            self.analysis_input.delete('1.0', tk.END)
            self.analysis_input.insert('1.0', text)
            self._set_status("Copied to analysis tab")

    def _refresh_history_lists(self):
        """Refresh history and favorites lists."""
        # History
        self.history_list.delete(0, tk.END)
        for entry in reversed(self.history_manager.history[-50:]):
            timestamp = entry.get('timestamp', '')[:16]
            preview = entry.get('original', '')[:40].replace('\n', ' ')
            score = entry.get('analysis', {}).get('overall_score', '--')
            self.history_list.insert(tk.END, f"  [{score}] {timestamp} - {preview}...")

        # Favorites
        self.favorites_list.delete(0, tk.END)
        for entry in self.history_manager.favorites:
            name = entry.get('name', 'Unnamed')
            preview = entry.get('optimized', '')[:35].replace('\n', ' ')
            self.favorites_list.insert(tk.END, f"  {name}: {preview}...")

    def _on_history_select(self, event=None):
        """Handle history selection."""
        pass  # Could show preview

    def _load_from_history(self, event=None):
        """Load selected history item."""
        selection = self.history_list.curselection()
        if not selection:
            return

        idx = len(self.history_manager.history) - 1 - selection[0]
        if 0 <= idx < len(self.history_manager.history):
            entry = self.history_manager.history[idx]
            self.input_text.delete('1.0', tk.END)
            self.input_text.insert('1.0', entry.get('original', ''))
            self.output_text.delete('1.0', tk.END)
            self.output_text.insert('1.0', entry.get('optimized', ''))
            self._on_input_change()
            self.notebook.select(0)
            self._set_status("Loaded from history")

    def _history_to_favorites(self):
        """Add selected history item to favorites."""
        selection = self.history_list.curselection()
        if not selection:
            return

        idx = len(self.history_manager.history) - 1 - selection[0]
        if 0 <= idx < len(self.history_manager.history):
            entry = self.history_manager.history[idx]
            self.history_manager.add_to_favorites(
                entry.get('original', ''),
                entry.get('optimized', '')
            )
            self._refresh_history_lists()
            self._update_stats()
            self._set_status("Added to favorites!")

    def _load_from_favorites(self, event=None):
        """Load selected favorite."""
        selection = self.favorites_list.curselection()
        if not selection:
            return

        entry = self.history_manager.favorites[selection[0]]
        self.input_text.delete('1.0', tk.END)
        self.input_text.insert('1.0', entry.get('original', ''))
        self.output_text.delete('1.0', tk.END)
        self.output_text.insert('1.0', entry.get('optimized', ''))
        self._on_input_change()
        self.notebook.select(0)
        self._set_status("Loaded from favorites")

    def _remove_favorite(self):
        """Remove selected favorite."""
        selection = self.favorites_list.curselection()
        if not selection:
            return

        self.history_manager.remove_favorite(selection[0])
        self._refresh_history_lists()
        self._update_stats()
        self._set_status("Removed from favorites")

    def _clear_history(self):
        """Clear all history."""
        if messagebox.askyesno("Clear History", "Are you sure you want to clear all history?"):
            self.history_manager.clear_history()
            self._refresh_history_lists()
            self._update_stats()
            self._set_status("History cleared")

    def _save_api_settings(self):
        """Save API settings."""
        self.settings['openai_api_key'] = self.openai_key.get()
        self.settings['anthropic_api_key'] = self.anthropic_key.get()
        self._save_settings()

        # Update providers
        self.providers['openai'] = OpenAIProvider(self.settings.get('openai_api_key', ''))
        self.providers['anthropic'] = AnthropicProvider(self.settings.get('anthropic_api_key', ''))

        self.settings_status.config(text="Settings saved!")
        self.root.after(3000, lambda: self.settings_status.config(text=""))

    def _update_stats(self):
        """Update header stats."""
        self.stats_label.config(
            text=f"History: {len(self.history_manager.history)} | Favorites: {len(self.history_manager.favorites)}"
        )

    def _set_status(self, message: str, error: bool = False):
        """Set status bar message."""
        color = self.colors['error'] if error else self.colors['text_secondary']
        self.status_label.config(text=message, fg=color)

    def run(self):
        """Start the application."""
        self.root.mainloop()


def main():
    """Main entry point."""
    app = PromptEngineerUltimate()
    app.run()


if __name__ == "__main__":
    main()
