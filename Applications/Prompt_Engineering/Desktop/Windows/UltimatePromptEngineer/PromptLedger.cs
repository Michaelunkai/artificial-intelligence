using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace UltimatePromptEngineer;

public sealed class PromptLedger
{
    public const int DefaultRetentionLimit = int.MaxValue;
    private static readonly Regex AuthorizationAssignment = new(
        @"(?<prefix>[""']?authorization[""']?\s*[:=]\s*)(?<quote>[""']?)(?<value>(?(quote)[^""']*|[^\r\n,;}]+))",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);
    private static readonly Regex SecretAssignment = new(
        @"(?<prefix>[""']?(?:api[-_ ]?key|access[-_ ]?token|refresh[-_ ]?token|id[-_ ]?token|client[-_ ]?secret|bearer|token|secret|password)[""']?\s*[:=]\s*)(?<quote>[""']?)(?<value>(?(quote)[^""']+|(?:Bearer\s+)?[^\s""',;}]+))",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);
    private static readonly Regex BearerValue = new(
        @"\bBearer\s+[A-Za-z0-9._~+/=-]+",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);
    private static readonly Regex BasicValue = new(
        @"\bBasic\s+[A-Za-z0-9._~+/=-]+",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);
    private readonly List<LedgerEntry> _entries = [];

    public PromptLedger(int retentionLimit = DefaultRetentionLimit)
    {
        if (retentionLimit < 1) throw new ArgumentOutOfRangeException(nameof(retentionLimit));
        RetentionLimit = retentionLimit;
    }

    public int RetentionLimit { get; }
    public IReadOnlyList<LedgerEntry> Entries => _entries;

    public LedgerEntry Capture(
        string content,
        string kind = "User input",
        string? strategy = null,
        string? provider = null,
        string? model = null,
        string? error = null,
        DateTimeOffset? timestamp = null)
    {
        var entry = new LedgerEntry(
            Guid.NewGuid(),
            timestamp ?? DateTimeOffset.UtcNow,
            kind ?? "User input",
            Redact(content ?? string.Empty) ?? string.Empty,
            strategy,
            provider,
            model,
            Redact(error));
        _entries.Add(entry);
        TrimToRetention();
        return entry;
    }

    public void Replace(IEnumerable<LedgerEntry> entries)
    {
        _entries.Clear();
        _entries.AddRange(Retain(entries
            .Where(entry => entry is not null)
            .Select(entry => entry with
            {
                Content = Redact(entry.Content) ?? string.Empty,
                Error = Redact(entry.Error)
            })));
    }

    public string BuildContext()
    {
        var output = new StringBuilder();
        foreach (var entry in _entries)
        {
            output.AppendLine($"[{entry.Kind}]");
            output.AppendLine(entry.Content);
            output.AppendLine();
        }

        return output.ToString().TrimEnd();
    }

    public void ResetWith(string content)
    {
        _entries.Clear();
        Capture(content);
    }

    private void TrimToRetention()
    {
        if (_entries.Count > RetentionLimit)
            _entries.RemoveRange(0, _entries.Count - RetentionLimit);
    }

    private IEnumerable<LedgerEntry> Retain(IEnumerable<LedgerEntry> entries) =>
        RetentionLimit == int.MaxValue ? entries : entries.TakeLast(RetentionLimit);

    internal static string? Redact(string? value)
    {
        if (string.IsNullOrEmpty(value)) return value;
        var redacted = AuthorizationAssignment.Replace(value, match =>
        {
            var prefix = match.Groups["prefix"].Value;
            var quote = match.Groups["quote"].Value;
            return $"{prefix}{quote}[REDACTED_SECRET]{quote}";
        });
        redacted = SecretAssignment.Replace(redacted, match =>
        {
            var prefix = match.Groups["prefix"].Value;
            var quote = match.Groups["quote"].Value;
            var secret = match.Groups["value"].Value;
            var bearer = secret.StartsWith("Bearer", StringComparison.OrdinalIgnoreCase)
                ? "Bearer "
                : string.Empty;
            return $"{prefix}{quote}{bearer}[REDACTED_SECRET]{quote}";
        });
        redacted = BearerValue.Replace(redacted, "Bearer [REDACTED_SECRET]");
        return BasicValue.Replace(redacted, "Basic [REDACTED_SECRET]");
    }
}

public sealed record LedgerEntry(
    Guid Id,
    DateTimeOffset Timestamp,
    string Kind,
    string Content,
    string? Strategy = null,
    string? Provider = null,
    string? Model = null,
    string? Error = null);

public sealed record PromptSession(
    IReadOnlyList<LedgerEntry> Entries,
    string? SelectedStrategy,
    string? SelectedProvider,
    string? SelectedModel,
    DateTimeOffset SavedAtUtc,
    string? SelectedAudience = null,
    bool? AddChecklist = null);

public sealed record VersionedPromptSession(int Version, PromptSession Session);

public sealed class PromptSessionStore
{
    public const int CurrentVersion = 1;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    public PromptSessionStore(string path, int retentionLimit = PromptLedger.DefaultRetentionLimit)
    {
        Path = path;
        RetentionLimit = retentionLimit;
    }

    public string Path { get; }
    public int RetentionLimit { get; }

    public void Save(PromptSession session)
    {
        var directory = System.IO.Path.GetDirectoryName(Path);
        if (!string.IsNullOrWhiteSpace(directory)) Directory.CreateDirectory(directory);
        var tempPath = $"{Path}.{Guid.NewGuid():N}.tmp";
        var safeSession = session with
        {
            Entries = Retain(session.Entries)
                .Select(entry => entry with
                {
                    Content = PromptLedger.Redact(entry.Content) ?? string.Empty,
                    Error = PromptLedger.Redact(entry.Error)
                })
                .ToArray()
        };
        try
        {
            var envelope = new VersionedPromptSession(CurrentVersion, safeSession);
            File.WriteAllText(tempPath, JsonSerializer.Serialize(envelope, JsonOptions), Encoding.UTF8);
            File.Move(tempPath, Path, true);
        }
        finally
        {
            if (File.Exists(tempPath)) File.Delete(tempPath);
        }
    }

    public PromptSession? TryLoad()
    {
        if (!File.Exists(Path)) return null;
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(Path));
            var root = document.RootElement;
            PromptSession? session;
            if (root.TryGetProperty("version", out var versionElement))
            {
                if (!versionElement.TryGetInt32(out var version) || version != CurrentVersion)
                    return null;
                if (!root.TryGetProperty("session", out var sessionElement))
                    return null;
                session = sessionElement.Deserialize<PromptSession>(JsonOptions);
            }
            else
            {
                // Migrate the immediately preceding unversioned session shape in memory.
                session = root.Deserialize<PromptSession>(JsonOptions);
            }

            if (session is null) return null;
            var entries = session.Entries ?? Array.Empty<LedgerEntry>();
            return session with
            {
                Entries = Retain(entries
                    .Where(entry => entry.Id != Guid.Empty && !string.IsNullOrWhiteSpace(entry.Kind))
                    .Select(entry => entry with
                    {
                        Content = PromptLedger.Redact(entry.Content) ?? string.Empty,
                        Error = PromptLedger.Redact(entry.Error)
                    })
                    .ToArray())
                    .ToArray()
            };
        }
        catch (JsonException)
        {
            return null;
        }
        catch (IOException)
        {
            return null;
        }
    }

    private IEnumerable<LedgerEntry> Retain(IEnumerable<LedgerEntry> entries) =>
        RetentionLimit == int.MaxValue ? entries : entries.TakeLast(RetentionLimit);
}
