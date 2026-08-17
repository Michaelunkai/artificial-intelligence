using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace UltimatePromptEngineer;

public sealed class MainForm : Form
{
    private static readonly Color CanvasColor = Color.FromArgb(244, 247, 249);
    private static readonly Color SurfaceColor = Color.White;
    private static readonly Color SurfaceSubtleColor = Color.FromArgb(248, 250, 251);
    private static readonly Color InkColor = Color.FromArgb(31, 41, 51);
    private static readonly Color MutedColor = Color.FromArgb(91, 104, 114);
    private static readonly Color BorderColor = Color.FromArgb(214, 223, 228);
    private static readonly Color AccentColor = Color.FromArgb(13, 107, 92);
    private static readonly Color AccentSoftColor = Color.FromArgb(226, 243, 239);
    private static readonly Color OutputColor = Color.FromArgb(19, 35, 40);
    private static readonly Color OutputInkColor = Color.FromArgb(241, 247, 246);
    private static readonly Color RemoteColor = Color.FromArgb(112, 72, 0);

    private static string GetSessionPath()
    {
        var overridePath = Environment.GetEnvironmentVariable("ULTIMATE_PROMPT_ENGINEER_SESSION_PATH");
        if (!string.IsNullOrWhiteSpace(overridePath))
            return Path.GetFullPath(overridePath);

        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "UltimatePromptEngineer",
            "session.json");
    }

    private readonly PromptBuilder _builder = new();
    private readonly PromptFileSafety _fileSafety = new();
    private readonly PromptLedger _ledger = new();
    private readonly PromptSessionStore _sessionStore = new(GetSessionPath());
    private readonly GeminiEnhancer _enhancer = new();
    private readonly TextBox _input = new()
    {
        Multiline = true,
        AcceptsTab = true,
        ScrollBars = ScrollBars.Vertical,
        Font = new Font("Consolas", 10),
        Dock = DockStyle.Fill,
        BorderStyle = BorderStyle.FixedSingle,
        BackColor = SurfaceColor,
        ForeColor = InkColor,
        PlaceholderText = "Paste the task, background, examples, and facts to preserve."
    };
    private readonly TextBox _requirements = new()
    {
        Multiline = true,
        AcceptsTab = true,
        ScrollBars = ScrollBars.Vertical,
        Font = new Font("Consolas", 10),
        Dock = DockStyle.Fill,
        BorderStyle = BorderStyle.FixedSingle,
        BackColor = SurfaceColor,
        ForeColor = InkColor,
        PlaceholderText = "Add deadlines, exclusions, format rules, acceptance checks, or open questions."
    };
    private readonly TextBox _output = new()
    {
        Multiline = true,
        ScrollBars = ScrollBars.Vertical,
        ReadOnly = true,
        Font = new Font("Consolas", 10),
        Dock = DockStyle.Fill,
        BorderStyle = BorderStyle.FixedSingle,
        BackColor = OutputColor,
        ForeColor = OutputInkColor
    };
    private readonly TextBox _apiKey = new()
    {
        PlaceholderText = "Session-only key (not saved)",
        Dock = DockStyle.Fill,
        UseSystemPasswordChar = true,
        Enabled = false,
        MinimumSize = new Size(150, 28),
        BackColor = SurfaceSubtleColor,
        ForeColor = InkColor
    };
    private readonly ComboBox _strategy = new()
    {
        DropDownStyle = ComboBoxStyle.DropDownList,
        Dock = DockStyle.Fill,
        MinimumSize = new Size(140, 28),
        BackColor = SurfaceColor,
        ForeColor = InkColor
    };
    private readonly ComboBox _intent = new()
    {
        DropDownStyle = ComboBoxStyle.DropDownList,
        Dock = DockStyle.Fill,
        MinimumSize = new Size(120, 28),
        BackColor = SurfaceColor,
        ForeColor = InkColor
    };
    private readonly ComboBox _audience = new()
    {
        DropDownStyle = ComboBoxStyle.DropDownList,
        Dock = DockStyle.Fill,
        MinimumSize = new Size(120, 28),
        BackColor = SurfaceColor,
        ForeColor = InkColor
    };
    private readonly CheckBox _checklist = new()
    {
        Text = "Include completion checklist",
        Checked = true,
        AutoSize = false,
        Dock = DockStyle.Fill,
        TextAlign = ContentAlignment.MiddleLeft
    };
    private readonly CheckBox _enableEnhancement = new()
    {
        Text = "Enable optional Gemini",
        AutoSize = false,
        Dock = DockStyle.Fill,
        TextAlign = ContentAlignment.MiddleLeft,
        ForeColor = InkColor
    };
    private readonly ListBox _history = new()
    {
        Dock = DockStyle.Bottom,
        Height = 110,
        BorderStyle = BorderStyle.FixedSingle,
        Font = new Font("Segoe UI", 9),
        BackColor = SurfaceSubtleColor,
        ForeColor = MutedColor,
        TabStop = false
    };
    private readonly Label _status = new()
    {
        AutoSize = false,
        Dock = DockStyle.Fill,
        ForeColor = MutedColor,
        Text = "Local prompt ready. Add context above; no API key or network is needed.",
        TextAlign = ContentAlignment.MiddleLeft,
        AutoEllipsis = true
    };
    private readonly Label _mode = new()
    {
        AutoSize = true,
        ForeColor = AccentColor,
        BackColor = AccentSoftColor,
        Text = "Local draft",
        Padding = new Padding(8, 4, 8, 4),
        TextAlign = ContentAlignment.MiddleCenter
    };
    private readonly ProgressBar _progress = new()
    {
        Width = 110,
        Height = 18,
        Style = ProgressBarStyle.Marquee,
        Visible = false,
        TabStop = false,
        AccessibleName = "Provider progress"
    };
    private readonly Button _generateButton;
    private readonly Button _enhanceButton;
    private CancellationTokenSource? _enhancementCancellation;
    private string _lastCapturedSource = string.Empty;
    private string _lastCapturedRequirements = string.Empty;
    private long _draftRevision;
    private bool _restoringSession;

    public MainForm()
    {
        Text = "Ultimate Prompt Engineer";
        MinimumSize = new Size(960, 650);
        Size = new Size(1360, 840);
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.Dpi;
        AutoScaleDimensions = new SizeF(96F, 96F);
        KeyPreview = true;
        BackColor = CanvasColor;
        ForeColor = InkColor;
        Font = new Font("Segoe UI", 10);

        _input.AccessibleName = "Source context";
        _input.AccessibleDescription = "Enter the request and all background details that should remain in the generated prompt.";
        _input.TabIndex = 0;
        _requirements.AccessibleName = "Requirements and constraints";
        _requirements.AccessibleDescription = "Enter explicit requirements, deadlines, exclusions, formats, checks, or open questions.";
        _requirements.TabIndex = 1;
        _output.AccessibleName = "Ready-to-send prompt";
        _output.AccessibleDescription = "Generated local prompt output. Read-only; use Copy or Export to reuse it.";
        _output.TabIndex = 7;
        _apiKey.AccessibleName = "Optional Gemini API key";
        _apiKey.AccessibleDescription = "Optional session-only provider key. Local generation never needs this field.";
        _apiKey.TabIndex = 13;
        _strategy.AccessibleName = "Prompt strategy";
        _strategy.AccessibleDescription = "Choose the working approach to apply while preserving the source.";
        _strategy.TabIndex = 2;
        _intent.AccessibleName = "Intent";
        _intent.AccessibleDescription = "Choose the primary outcome the generated prompt should request.";
        _intent.TabIndex = 3;
        _audience.AccessibleName = "Target agent";
        _audience.AccessibleDescription = "Choose the type of AI agent that will receive the generated prompt.";
        _audience.TabIndex = 4;
        _checklist.AccessibleName = "Include completion checklist";
        _checklist.AccessibleDescription = "Include a final completeness check in the generated prompt.";
        _checklist.TabIndex = 5;
        _enableEnhancement.AccessibleName = "Enable optional Gemini enhancement";
        _enableEnhancement.AccessibleDescription = "Opt in to the remote provider. Local generation remains available when this is off.";
        _enableEnhancement.TabIndex = 12;
        _history.AccessibleName = "Captured context ledger";

        _strategy.Items.AddRange(
        [
            "Preserve and deliver",
            "Plan and execute",
            "Diagnose and fix",
            "Rewrite with constraints",
            "Research and compare"
        ]);
        _intent.Items.AddRange(["Build or implement", "Analyze or research", "Write or rewrite", "Debug or review", "Plan a task"]);
        _audience.Items.AddRange(["Any AI agent", "Coding agent", "Research agent", "Writing agent"]);
        _strategy.SelectedIndex = 0;
        _intent.SelectedIndex = 0;
        _audience.SelectedIndex = 0;

        _generateButton = Button("Generate locally", AccentColor, Color.White);
        _generateButton.AccessibleName = "Generate local prompt";
        _generateButton.AccessibleDescription = "Generate the prompt locally without an API key, account, login, or network.";
        _generateButton.TabIndex = 6;
        _generateButton.Click += GenerateLocalPrompt;

        _enhanceButton = Button("Enhance remotely", RemoteColor, Color.White);
        _enhanceButton.AccessibleName = "Enhance prompt with optional Gemini";
        _enhanceButton.AccessibleDescription = "Use the optional provider only after it is enabled and a session-only key is entered.";
        _enhanceButton.TabIndex = 14;
        _enhanceButton.Enabled = false;
        _enhanceButton.Click += EnhanceAsync;

        _input.TextChanged += InputChanged;
        _requirements.TextChanged += RequirementsChanged;
        _strategy.SelectedIndexChanged += SelectionChanged;
        _intent.SelectedIndexChanged += SelectionChanged;
        _audience.SelectedIndexChanged += SelectionChanged;
        _checklist.CheckedChanged += (_, _) => RefreshPrompt();
        _enableEnhancement.CheckedChanged += OptionalEnhancementChanged;

        RestoreSession();

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 3,
            BackColor = BackColor,
            Margin = Padding.Empty,
            Padding = Padding.Empty
        };
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 88));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 96));
        root.Controls.Add(CreateHeader(), 0, 0);
        root.Controls.Add(CreateWorkspace(), 0, 1);
        root.Controls.Add(CreateProviderBar(), 0, 2);
        Controls.Add(root);

        RefreshPrompt();
        RefreshHistory();
        KeyDown += MainFormKeyDown;
        ActiveControl = _input;
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        _enhancementCancellation?.Cancel();
        CaptureCurrentDraft();
        try
        {
            SaveSession();
        }
        catch (IOException)
        {
            _status.Text = "The local session could not be saved, but the generated prompt remains available.";
        }
        catch (UnauthorizedAccessException)
        {
            _status.Text = "The local session folder is not writable, but the generated prompt remains available.";
        }
        base.OnFormClosing(e);
    }

    private Control CreateHeader()
    {
        var header = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            Padding = new Padding(24, 16, 24, 0),
            BackColor = SurfaceColor,
            AccessibleName = "Application header"
        };
        header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        header.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

        var titlePanel = new Panel { Dock = DockStyle.Fill };
        titlePanel.Controls.Add(new Label
        {
            Text = "Ultimate Prompt Engineer",
            Font = new Font("Segoe UI", 18, FontStyle.Bold),
            AutoSize = true
        });
        titlePanel.Controls.Add(new Label
        {
            Text = "Turn a rough request into a clear, durable prompt.",
            ForeColor = MutedColor,
            AutoSize = true,
            Top = 33
        });
        header.Controls.Add(titlePanel, 0, 0);
        header.Controls.Add(new Label
        {
            Text = "LOCAL FIRST  •  NO ACCOUNT REQUIRED",
            AutoSize = true,
            ForeColor = AccentColor,
            BackColor = AccentSoftColor,
            Anchor = AnchorStyles.Right,
            Padding = new Padding(10, 7, 10, 7)
        }, 1, 0);
        return header;
    }

    private Control CreateWorkspace()
    {
        var split = new SplitContainer
        {
            Dock = DockStyle.Fill,
            SplitterDistance = 520,
            Padding = new Padding(20, 12, 20, 12),
            BackColor = BackColor,
            IsSplitterFixed = false,
            AccessibleName = "Prompt workspace"
        };
        split.Panel1.Padding = new Padding(0, 0, 8, 0);
        split.Panel2.Padding = new Padding(8, 0, 0, 0);
        split.Panel1.Controls.Add(CreateSourcePanel());
        split.Panel2.Controls.Add(CreateOutputPanel());
        return split;
    }

    private Control CreateSourcePanel()
    {
        var panel = Surface();
        panel.AccessibleName = "Source and requirements review";

        var title = new Label
        {
            Text = "1  Describe the task",
            Font = new Font("Segoe UI", 12, FontStyle.Bold),
            Dock = DockStyle.Top,
            Height = 32,
            ForeColor = InkColor
        };
        var subtitle = new Label
        {
            Text = "Paste the raw request above, then add explicit constraints below. Your draft stays local until you choose an optional provider.",
            Dock = DockStyle.Top,
            Height = 36,
            ForeColor = MutedColor,
            AutoEllipsis = true
        };
        var editors = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 4,
            Margin = Padding.Empty,
            Padding = new Padding(0, 8, 0, 8)
        };
        editors.RowStyles.Add(new RowStyle(SizeType.Absolute, 24));
        editors.RowStyles.Add(new RowStyle(SizeType.Percent, 55));
        editors.RowStyles.Add(new RowStyle(SizeType.Absolute, 24));
        editors.RowStyles.Add(new RowStyle(SizeType.Percent, 45));
        editors.Controls.Add(FieldLabel("Source context"), 0, 0);
        editors.Controls.Add(_input, 0, 1);
        editors.Controls.Add(FieldLabel("Requirements and constraints"), 0, 2);
        editors.Controls.Add(_requirements, 0, 3);

        var tools = new TableLayoutPanel
        {
            Dock = DockStyle.Bottom,
            Height = 126,
            ColumnCount = 3,
            RowCount = 3,
            Padding = new Padding(0, 10, 0, 0)
        };
        tools.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 42));
        tools.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 29));
        tools.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 29));
        tools.RowStyles.Add(new RowStyle(SizeType.Absolute, 24));
        tools.RowStyles.Add(new RowStyle(SizeType.Percent, 54));
        tools.RowStyles.Add(new RowStyle(SizeType.Percent, 46));
        var shapeLabel = FieldLabel("2  Shape the result");
        tools.Controls.Add(shapeLabel, 0, 0);
        tools.SetColumnSpan(shapeLabel, 3);
        tools.Controls.Add(Labeled("Strategy", _strategy), 0, 1);
        tools.Controls.Add(Labeled("Intent", _intent), 1, 1);
        tools.Controls.Add(Labeled("Target agent", _audience), 2, 1);
        tools.Controls.Add(_checklist, 0, 2);
        tools.SetColumnSpan(_checklist, 2);
        tools.Controls.Add(_generateButton, 2, 2);

        var historyLabel = new Label
        {
            Text = "Recent captures  •  local session only",
            Dock = DockStyle.Bottom,
            Height = 27,
            ForeColor = AccentColor,
            Padding = new Padding(0, 6, 0, 0)
        };

        panel.Controls.Add(editors);
        panel.Controls.Add(tools);
        panel.Controls.Add(_history);
        panel.Controls.Add(historyLabel);
        panel.Controls.Add(subtitle);
        panel.Controls.Add(title);
        return panel;
    }

    private Control CreateOutputPanel()
    {
        var panel = Surface();
        panel.AccessibleName = "Generated prompt output";

        var titleBar = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            Height = 34,
            ColumnCount = 2
        };
        titleBar.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        titleBar.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        titleBar.Controls.Add(new Label
        {
            Text = "3  Generated prompt",
            Font = new Font("Segoe UI", 12, FontStyle.Bold),
            ForeColor = InkColor,
            AutoSize = true
        }, 0, 0);
        titleBar.Controls.Add(_mode, 1, 0);

        var actions = new TableLayoutPanel
        {
            Dock = DockStyle.Bottom,
            Height = 60,
            ColumnCount = 6,
            Padding = new Padding(0, 9, 0, 0),
            AccessibleName = "Prompt commands"
        };
        actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        actions.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        actions.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        actions.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        actions.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        actions.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

        var copy = Button("Copy", AccentColor, Color.White);
        copy.AccessibleName = "Copy generated prompt";
        copy.AccessibleDescription = "Copy the complete generated prompt to the clipboard.";
        copy.TabIndex = 8;
        copy.Click += (_, _) => CopyOutput();
        var import = Button("Import source", InkColor, Color.White);
        import.AccessibleName = "Import source file";
        import.AccessibleDescription = "Import a supported local text file into source context.";
        import.TabIndex = 9;
        import.Click += Import;
        var export = Button("Export", InkColor, Color.White);
        export.AccessibleName = "Export generated prompt";
        export.AccessibleDescription = "Save the complete generated prompt as a text file.";
        export.TabIndex = 10;
        export.Click += Export;
        var reset = Button("Start over", Color.FromArgb(235, 240, 242), InkColor);
        reset.AccessibleName = "Reset source and requirements";
        reset.AccessibleDescription = "Clear the editable source and requirements fields and start a new local capture.";
        reset.TabIndex = 11;
        reset.Click += ResetSource;

        actions.Controls.Add(_status, 0, 0);
        actions.Controls.Add(_progress, 1, 0);
        actions.Controls.Add(copy, 2, 0);
        actions.Controls.Add(import, 3, 0);
        actions.Controls.Add(export, 4, 0);
        actions.Controls.Add(reset, 5, 0);

        panel.Controls.Add(_output);
        panel.Controls.Add(actions);
        panel.Controls.Add(titleBar);
        return panel;
    }

    private Control CreateProviderBar()
    {
        var bar = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(24, 10, 24, 8),
            BackColor = SurfaceColor,
            ColumnCount = 4,
            RowCount = 3,
            AccessibleName = "Optional provider commands"
        };
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 38));
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 22));
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25));
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 15));
        bar.RowStyles.Add(new RowStyle(SizeType.Absolute, 24));
        bar.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
        bar.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        var heading = new Label
        {
            Text = "Optional remote enhancement",
            Dock = DockStyle.Fill,
            ForeColor = InkColor,
            TextAlign = ContentAlignment.MiddleLeft
        };
        var local = new Label
        {
            Text = "Local generation is always ready offline.",
            Dock = DockStyle.Fill,
            ForeColor = AccentColor,
            TextAlign = ContentAlignment.MiddleLeft,
            AutoEllipsis = true
        };
        var note = new Label
        {
            Text = "Off by default. Any key stays in memory for this session; local output remains the fallback.",
            Dock = DockStyle.Fill,
            ForeColor = MutedColor,
            AutoEllipsis = true,
            TextAlign = ContentAlignment.MiddleLeft
        };
        bar.Controls.Add(heading, 0, 0);
        bar.SetColumnSpan(heading, 4);
        bar.Controls.Add(local, 0, 1);
        bar.Controls.Add(_enableEnhancement, 1, 1);
        bar.Controls.Add(_apiKey, 2, 1);
        bar.Controls.Add(_enhanceButton, 3, 1);
        bar.Controls.Add(note, 0, 2);
        bar.SetColumnSpan(note, 4);
        return bar;
    }

    private static Panel Surface() => new()
    {
        Dock = DockStyle.Fill,
        BackColor = SurfaceColor,
        Padding = new Padding(16),
        BorderStyle = BorderStyle.FixedSingle
    };

    private static Control Labeled(string label, Control control)
    {
        var panel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            RowCount = 2,
            ColumnCount = 1,
            Margin = new Padding(0, 0, 10, 0),
            Padding = Padding.Empty
        };
        panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 22));
        panel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        panel.Controls.Add(FieldLabel(label), 0, 0);
        panel.Controls.Add(control, 0, 1);
        return panel;
    }

    private static Label FieldLabel(string text) => new()
    {
        Text = text,
        Dock = DockStyle.Fill,
        ForeColor = MutedColor,
        Font = new Font("Segoe UI", 9, FontStyle.Bold),
        TextAlign = ContentAlignment.MiddleLeft
    };

    private static Button Button(string text, Color backColor, Color foreColor) => new()
    {
        Text = text,
        AutoSize = false,
        MinimumSize = new Size(92, 36),
        Padding = new Padding(12, 7, 12, 7),
        Dock = DockStyle.Fill,
        FlatStyle = FlatStyle.Flat,
        BackColor = backColor,
        ForeColor = foreColor,
        Margin = new Padding(6, 4, 0, 0),
        Font = new Font("Segoe UI", 9.5F, FontStyle.Bold),
        Cursor = Cursors.Hand,
        AccessibleRole = AccessibleRole.PushButton,
        UseVisualStyleBackColor = false,
        FlatAppearance =
        {
            BorderColor = BorderColor,
            BorderSize = 1,
            MouseOverBackColor = backColor
        }
    };

    private void InputChanged(object? sender, EventArgs args)
    {
        if (!_restoringSession)
            DraftChanged();
        RefreshHistory();
        RefreshPrompt();
    }

    private void RequirementsChanged(object? sender, EventArgs args)
    {
        if (!_restoringSession)
            DraftChanged();
        RefreshHistory();
        RefreshPrompt();
    }

    private void SelectionChanged(object? sender, EventArgs args)
    {
        _draftRevision++;
        RefreshPrompt();
    }

    private void DraftChanged()
    {
        _draftRevision++;
        _enhancementCancellation?.Cancel();
    }

    private void RestoreSession()
    {
        var session = _sessionStore.TryLoad();
        if (session is null || session.Entries.Count == 0)
            return;

        _ledger.Replace(session.Entries);
        _restoringSession = true;
        try
        {
            var source = session.Entries.LastOrDefault(entry =>
                entry.Kind is "Source context" or "Current source snapshot" or "User input");
            var requirements = session.Entries.LastOrDefault(entry => entry.Kind == "Requirements and constraints");
            if (source is not null)
                _input.Text = source.Content;
            if (requirements is not null)
                _requirements.Text = requirements.Content;
            _lastCapturedSource = source?.Content ?? string.Empty;
            _lastCapturedRequirements = requirements?.Content ?? string.Empty;

            if (session.SelectedStrategy is not null)
            {
                if (_strategy.Items.Contains(session.SelectedStrategy))
                    _strategy.SelectedItem = session.SelectedStrategy;
                else if (_intent.Items.Contains(session.SelectedStrategy))
                    _intent.SelectedItem = session.SelectedStrategy;
            }
            if (session.SelectedAudience is not null && _audience.Items.Contains(session.SelectedAudience))
                _audience.SelectedItem = session.SelectedAudience;
            if (session.AddChecklist is bool addChecklist)
                _checklist.Checked = addChecklist;
        }
        finally
        {
            _restoringSession = false;
        }
    }

    private void SaveSession()
    {
        CaptureCurrentDraft();
        _sessionStore.Save(new PromptSession(
            _ledger.Entries,
            _strategy.SelectedItem?.ToString(),
            "Gemini Developer API",
            GeminiEnhancer.ModelId,
            DateTimeOffset.UtcNow,
            _audience.SelectedItem?.ToString(),
            _checklist.Checked));
    }

    private void CaptureCurrentDraft()
    {
        if (string.Equals(_input.Text, _lastCapturedSource, StringComparison.Ordinal)
            && string.Equals(_requirements.Text, _lastCapturedRequirements, StringComparison.Ordinal))
            return;

        if (!string.Equals(_input.Text, _lastCapturedSource, StringComparison.Ordinal))
        {
            _ledger.Capture(_input.Text, "Source context");
            _lastCapturedSource = _input.Text;
        }
        if (!string.Equals(_requirements.Text, _lastCapturedRequirements, StringComparison.Ordinal))
        {
            _ledger.Capture(_requirements.Text, "Requirements and constraints");
            _lastCapturedRequirements = _requirements.Text;
        }
        RefreshHistory();
    }

    private string BuildPromptContext()
    {
        var history = _ledger.BuildContext();
        var current = _builder.CreateStructuredSource(_input.Text, _requirements.Text);
        if (string.IsNullOrWhiteSpace(history))
            return current;

        var committed = _builder.CreateStructuredSource(_lastCapturedSource, _lastCapturedRequirements);
        if (string.Equals(current, committed, StringComparison.Ordinal))
            return history;

        return string.Join(
            Environment.NewLine,
            [
                history,
                string.Empty,
                "[Current draft - not yet committed to the local ledger]",
                current
            ]);
    }

    private void RefreshPrompt()
    {
        var intent = _intent.SelectedItem?.ToString() ?? "Build or implement";
        var audience = _audience.SelectedItem?.ToString() ?? "Any AI agent";
        var strategy = _strategy.SelectedItem?.ToString() ?? "Preserve and deliver";
        _output.Text = _builder.Build(
            BuildPromptContext(),
            string.Empty,
            intent,
            audience,
            strategy,
            _checklist.Checked);
        _mode.Text = _enableEnhancement.Checked ? "Local + optional AI" : "Local template";
        _status.Text = string.IsNullOrWhiteSpace(_input.Text) && string.IsNullOrWhiteSpace(_requirements.Text)
            ? "Local prompt ready. Add context above; no API key or network is needed."
            : "Local prompt ready. No API key or network is needed.";
    }

    private void RefreshHistory()
    {
        _history.BeginUpdate();
        try
        {
            _history.Items.Clear();
            foreach (var entry in _ledger.Entries.TakeLast(6).Reverse())
            {
                _history.Items.Add(
                    $"{entry.Timestamp.LocalDateTime:t}  {entry.Kind}  ({entry.Content.Length:N0} characters)");
            }
        }
        finally
        {
            _history.EndUpdate();
        }
    }

    private void GenerateLocalPrompt(object? sender, EventArgs e)
    {
        CaptureCurrentDraft();
        RefreshPrompt();
        _status.Text = "Generated locally from the current captures. No API key, account, login, or network was used.";
    }

    private void CopyOutput()
    {
        try
        {
            Clipboard.SetText(_output.Text);
            _status.Text = "Copied the complete local prompt to the clipboard.";
        }
        catch (ExternalException)
        {
            _status.Text = "The clipboard is busy. Try Copy again; the prompt remains available here.";
        }
        catch
        {
            _status.Text = "The clipboard is unavailable. The prompt remains available here and can still be exported.";
        }
    }

    private void Export(object? sender, EventArgs e)
    {
        using var dialog = new SaveFileDialog
        {
            Filter = "Text files (*.txt)|*.txt",
            FileName = "ultimate-prompt.txt",
            OverwritePrompt = false
        };
        if (dialog.ShowDialog(this) != DialogResult.OK)
            return;

        try
        {
            var path = _fileSafety.Export(
                Path.GetDirectoryName(dialog.FileName)!,
                Path.GetFileName(dialog.FileName),
                _output.Text);
            _status.Text = $"Exported {Path.GetFileName(path)}.";
        }
        catch (PromptFileSafetyException ex)
        {
            _status.Text = ex.Message;
        }
        catch
        {
            _status.Text = "The prompt could not be exported. Choose another local folder or filename.";
        }
    }

    private void Import(object? sender, EventArgs e)
    {
        using var dialog = new OpenFileDialog
        {
            Filter = _fileSafety.SupportedFileFilter,
            CheckFileExists = true,
            Multiselect = false
        };
        if (dialog.ShowDialog(this) != DialogResult.OK)
            return;

        try
        {
            var imported = _fileSafety.Import(dialog.FileName);
            _input.Text = imported.Text;
            _status.Text = $"Imported {imported.FileName} ({imported.Encoding.WebName}).";
        }
        catch (PromptFileSafetyException ex)
        {
            _status.Text = ex.Message;
        }
        catch
        {
            _status.Text = "The selected file could not be imported. Choose another supported local file.";
        }
    }

    private void ResetSource(object? sender, EventArgs e)
    {
        _enhancementCancellation?.Cancel();
        _input.Clear();
        _requirements.Clear();
        _ledger.ResetWith(string.Empty);
        _lastCapturedSource = string.Empty;
        _lastCapturedRequirements = string.Empty;
        RefreshHistory();
        RefreshPrompt();
        _status.Text = "Started a new local capture. No API key or network is needed.";
        _input.Select();
    }

    private void OptionalEnhancementChanged(object? sender, EventArgs e)
    {
        _apiKey.Enabled = _enableEnhancement.Checked;
        _enhanceButton.Enabled = _enableEnhancement.Checked;
        RefreshPrompt();
        if (_enableEnhancement.Checked)
            _status.Text = "Optional Gemini enhancement enabled. Local generation remains available without a key.";
    }

    private async void EnhanceAsync(object? sender, EventArgs e)
    {
        if (_enhancementCancellation is not null)
        {
            _enhancementCancellation.Cancel();
            _status.Text = "Canceling optional enhancement. The local prompt remains ready.";
            return;
        }

        if (!_enableEnhancement.Checked)
        {
            _status.Text = "Optional enhancement is off. The local prompt is ready without a key.";
            return;
        }

        CaptureCurrentDraft();
        var local = _output.Text;
        var immutableContext = BuildPromptContext();
        var requestRevision = _draftRevision;
        var cancellation = new CancellationTokenSource();
        _enhancementCancellation = cancellation;
        if (string.IsNullOrWhiteSpace(_apiKey.Text))
        {
            _enhancementCancellation = null;
            cancellation.Dispose();
            _status.Text = "No optional key entered. The complete local prompt remains ready to copy or export.";
            return;
        }

        try
        {
            _status.Text = "Enhancing with the optional Gemini provider...";
            _progress.Visible = true;
            _enhanceButton.Enabled = false;
            _enhanceButton.Text = "Cancel";
            var result = await _enhancer.EnhanceAsync(_apiKey.Text, immutableContext, cancellation.Token);
            if (requestRevision != _draftRevision || cancellation.IsCancellationRequested)
            {
                _output.Text = local;
                _mode.Text = "Local template";
                _status.Text = "Source changed while the optional provider ran. Its result was discarded; local output is current.";
                return;
            }
            _output.Text = _builder.EnsureSourcePreserved(result.UltimatePrompt, immutableContext);
            _mode.Text = $"{result.Provider} enhanced";
            _status.Text = $"Optional model result received (attempt {result.Attempt}); captured context retained.";
        }
        catch (GeminiQuotaException)
        {
            RestoreLocalAfterProvider(local, requestRevision);
            _status.Text = "Optional provider quota is unavailable. The local prompt and all captured context are intact.";
        }
        catch (GeminiCredentialException)
        {
            RestoreLocalAfterProvider(local, requestRevision);
            _status.Text = "Optional provider rejected the key. The local prompt remains ready.";
        }
        catch (OperationCanceledException)
        {
            RestoreLocalAfterProvider(local, requestRevision);
            _status.Text = "Optional provider request was canceled. The local prompt remains ready.";
        }
        catch (NormalizedProviderException ex)
        {
            RestoreLocalAfterProvider(local, requestRevision);
            _status.Text = ex.Kind switch
            {
                ProviderErrorKind.Authentication =>
                    "Optional provider rejected the key. The local prompt remains ready.",
                ProviderErrorKind.Quota =>
                    "Optional provider quota is unavailable. The local prompt and all captured context are intact.",
                ProviderErrorKind.Cancellation =>
                    "Optional provider request was canceled. The local prompt remains ready.",
                ProviderErrorKind.Timeout =>
                    "Optional provider timed out. No content was lost; the local prompt is ready.",
                ProviderErrorKind.InvalidResponse =>
                    "Optional provider returned an invalid response. No content was lost; the local prompt is ready.",
                _ =>
                    "Optional provider was unavailable. No content was lost; the local prompt is ready."
            };
        }
        catch
        {
            RestoreLocalAfterProvider(local, requestRevision);
            _status.Text = "Optional provider was unavailable. No content was lost; the local prompt is ready.";
        }
        finally
        {
            if (ReferenceEquals(_enhancementCancellation, cancellation))
            {
                _enhancementCancellation = null;
                _progress.Visible = false;
                _enhanceButton.Text = "Enhance";
                _enhanceButton.Enabled = _enableEnhancement.Checked;
            }
        }
    }

    private void RestoreLocalAfterProvider(string local, long requestRevision)
    {
        if (requestRevision == _draftRevision)
        {
            _output.Text = local;
            _mode.Text = "Template fallback";
            return;
        }

        RefreshPrompt();
        _mode.Text = "Local template";
    }

    private void MainFormKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Control && e.KeyCode == Keys.Enter)
        {
            GenerateLocalPrompt(this, EventArgs.Empty);
            e.SuppressKeyPress = true;
        }
        else if (e.Control && e.Shift && e.KeyCode == Keys.C)
        {
            CopyOutput();
            e.SuppressKeyPress = true;
        }
        else if (e.Control && e.KeyCode == Keys.E)
        {
            Export(this, EventArgs.Empty);
            e.SuppressKeyPress = true;
        }
    }
}
