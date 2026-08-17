using UltimatePromptEngineer;

internal static class PipelineIntegrationTests
{
    public static async Task RunAsync()
    {
        var source = """
            Build a small release checklist.
            Requirements: preserve the exact command, mention the Friday deadline, and ask one open question.
            Never delete existing files.
            """;

        var ledger = new PromptLedger();
        ledger.Capture(source, "User input", "Checklist strategy", "Fake local", "fake-v1",
            timestamp: new DateTimeOffset(2026, 8, 2, 12, 0, 0, TimeSpan.Zero));

        var context = ledger.BuildContext();
        var requirements = ExtractRequirements(context);
        Assert(requirements.Count == 4, "Requirement extraction must retain each explicit requirement.");
        Assert(requirements.Any(item => item.Contains("exact command", StringComparison.Ordinal)),
            "Requirement extraction must retain exactness constraints.");
        Assert(requirements.Any(item => item.Contains("Friday", StringComparison.Ordinal)),
            "Requirement extraction must retain deadline details.");
        Assert(requirements.Any(item => item.Contains("Never delete", StringComparison.Ordinal)),
            "Requirement extraction must retain negative constraints.");

        var classifier = new PromptClassifier();
        var intent = classifier.ClassifyIntent("Build or implement");
        var audience = classifier.ClassifyAudience("Coding agent");
        var specification = new PromptSpecification(source, intent, audience, true);

        var builder = new PromptBuilder();
        var composedPrompt = builder.Build(specification);
        Assert(composedPrompt.Contains("capable coding agent and build or implement", StringComparison.Ordinal),
            "Classification must feed the strategy composition boundary.");
        Assert(composedPrompt.Contains("# Completion check", StringComparison.Ordinal),
            "Selected completion strategy must be composed into the prompt.");
        Assert(builder.DecodeCanonicalSourceRecord(composedPrompt).Contains(source, StringComparison.Ordinal),
            "Strategy composition must preserve captured source losslessly.");

        var provider = new FakePromptProvider(
            new PromptProviderResponse("Fake local", "fake-v1", composedPrompt, RequestId: "fake-request-1"));
        var router = new PromptProviderRouter([provider]);
        var result = await router.GenerateAsync(
            PromptProviderKind.Local,
            new PromptProviderRequest(composedPrompt));

        Assert(result.Provider == "Fake local" && result.Model == "fake-v1",
            "Returned result must retain provider identity and model diagnostics.");
        Assert(result.RequestId == "fake-request-1" && result.Attempt == 1,
            "Returned result must retain request and attempt diagnostics.");
        Assert(result.UltimatePrompt == composedPrompt,
            "Returned result must carry the composed prompt.");

        var coverage = ReportCoverage(requirements, builder.DecodeCanonicalSourceRecord(result.UltimatePrompt));
        Assert(coverage.Total == 4 && coverage.Covered == 4 && coverage.Missing.Count == 0,
            "Coverage reporting must show all extracted requirements represented in the result.");

        var diagnostics = new PipelineDiagnostics(
            result.Provider,
            result.Model,
            result.Attempt,
            result.RequestId,
            coverage.Covered,
            coverage.Total);
        Assert(diagnostics.IsComplete && diagnostics.RequestId == "fake-request-1",
            "Pipeline diagnostics must summarize a complete returned result.");

        var tempDirectory = Path.Combine(Path.GetTempPath(), "UltimatePromptEngineerPipelineTests", Guid.NewGuid().ToString("N"));
        var sessionPath = Path.Combine(tempDirectory, "session.json");
        try
        {
            var store = new PromptSessionStore(sessionPath);
            store.Save(new PromptSession(
                ledger.Entries,
                PromptSpecificationText.Intent(intent),
                provider.Name,
                provider.Model,
                DateTimeOffset.UtcNow));
            var restored = store.TryLoad();
            Assert(restored is not null && restored.Entries.Single().Content == source,
                "The integration path must persist and restore the captured source used by the pipeline.");
        }
        finally
        {
            if (Directory.Exists(tempDirectory)) Directory.Delete(tempDirectory, true);
        }

        await RunFailurePathsAsync();
    }

    private static async Task RunFailurePathsAsync()
    {
        var builder = new PromptBuilder();
        var malformedPrompt = builder.Build((string)null!, "Build or implement", "Any AI agent", false);
        Assert(builder.DecodeCanonicalSourceRecord(malformedPrompt) == string.Empty,
            "Malformed null source must normalize to an empty canonical record instead of escaping the boundary.");
        AssertThrows<ArgumentOutOfRangeException>(
            () => new PromptClassifier().ClassifyIntent("unsupported intent"),
            "Unsupported intent must fail at the classification boundary.");

        var source = "Requirements: retain alpha, retain beta, retain gamma.";
        var ledger = new PromptLedger();
        ledger.Capture(source, "User input", "Failure-path strategy", "Failing fake", "failure-v1",
            timestamp: new DateTimeOffset(2026, 8, 2, 13, 0, 0, TimeSpan.Zero));
        var prompt = builder.Build(ledger.BuildContext(), "Build or implement", "Any AI agent", true);
        foreach (var provider in new IPromptProvider[]
        {
            new ThrowingProvider(ProviderErrorKind.Timeout),
            new ThrowingProvider(ProviderErrorKind.Cancellation),
            new ThrowingProvider(ProviderErrorKind.Quota)
        })
        {
            await AssertThrowsAsync<NormalizedProviderException>(
                () => provider.GenerateAsync(new PromptProviderRequest(prompt)),
                $"Provider {provider.Name} must expose deterministic normalized failure diagnostics.");
        }

        var requirements = new[] { "retain alpha", "retain beta", "retain gamma" };
        var omission = ReportCoverage(requirements, "retain alpha");
        Assert(omission.Covered == 1 && omission.Missing.SequenceEqual(["retain beta", "retain gamma"]),
            "Coverage diagnostics must identify omitted requirements.");

        var conflict = ReportConflicts(
            requirements,
            "retain alpha; do not retain beta; retain gamma");
        Assert(conflict.SequenceEqual(["retain beta"]),
            "Coverage diagnostics must identify a contradictory requirement result.");

        var failedSessionDirectory = Path.Combine(
            Path.GetTempPath(),
            "UltimatePromptEngineerPipelineFailureTests",
            Guid.NewGuid().ToString("N"));
        var failedSessionPath = Path.Combine(failedSessionDirectory, "session.json");
        try
        {
            try
            {
                await new ThrowingProvider(ProviderErrorKind.Quota).GenerateAsync(
                    new PromptProviderRequest(prompt));
            }
            catch (NormalizedProviderException ex) when (ex.Kind == ProviderErrorKind.Quota)
            {
                ledger.Capture(
                    "Provider quota failure",
                    "Provider diagnostic",
                    "Failure-path strategy",
                    "Failing fake",
                    "failure-v1",
                    error: ex.Message,
                    timestamp: new DateTimeOffset(2026, 8, 2, 13, 1, 0, TimeSpan.Zero));
            }

            var store = new PromptSessionStore(failedSessionPath);
            store.Save(new PromptSession(
                ledger.Entries,
                "Build or implement",
                "Failing fake",
                "failure-v1",
                DateTimeOffset.UtcNow));
            var restored = store.TryLoad();
            Assert(restored is not null
                && restored.Entries.Any(entry => entry.Content == source)
                && restored.Entries.Any(entry => entry.Kind == "Provider diagnostic"
                    && entry.Error == "Simulated quota failure"),
                "Persistence must restore captured source and normalized diagnostics after a failed request.");
        }
        finally
        {
            if (Directory.Exists(failedSessionDirectory)) Directory.Delete(failedSessionDirectory, true);
        }
    }

    private static IReadOnlyList<string> ExtractRequirements(string context) =>
        context.Split(["\r\n", "\n"], StringSplitOptions.RemoveEmptyEntries)
            .Select(line => line.Trim())
            .Where(line => line.StartsWith("Requirements:", StringComparison.Ordinal)
                || line.StartsWith("Never ", StringComparison.Ordinal))
            .SelectMany(line => line.StartsWith("Requirements:", StringComparison.Ordinal)
                ? line["Requirements:".Length..].Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
                : [line])
            .ToArray();

    private static CoverageReport ReportCoverage(IReadOnlyList<string> requirements, string result) =>
        new(
            requirements.Count,
            requirements.Count(requirement => result.Contains(requirement, StringComparison.Ordinal)),
            requirements.Where(requirement => !result.Contains(requirement, StringComparison.Ordinal)).ToArray());

    private static IReadOnlyList<string> ReportConflicts(
        IReadOnlyList<string> requirements,
        string result) =>
        requirements
            .Where(requirement => result.Contains($"do not {requirement}", StringComparison.Ordinal))
            .ToArray();

    private sealed class FakePromptProvider(PromptProviderResponse response) : IPromptProvider
    {
        public PromptProviderKind Kind => PromptProviderKind.Local;
        public string Name => response.Provider;
        public string Model => response.Model;
        public bool RequiresCredential => false;

        public Task<PromptProviderResponse> GenerateAsync(
            PromptProviderRequest request,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(response with { UltimatePrompt = request.CapturedContext });
        }
    }

    private sealed class ThrowingProvider(ProviderErrorKind errorKind) : IPromptProvider
    {
        public PromptProviderKind Kind => errorKind == ProviderErrorKind.Timeout
            ? PromptProviderKind.Local
            : PromptProviderKind.Remote;
        public string Name => $"Failing fake ({errorKind})";
        public string Model => "failure-v1";
        public bool RequiresCredential => false;

        public Task<PromptProviderResponse> GenerateAsync(
            PromptProviderRequest request,
            CancellationToken cancellationToken = default)
        {
            if (errorKind == ProviderErrorKind.Cancellation)
                throw new NormalizedProviderException(errorKind, "Simulated cancellation failure");
            if (errorKind == ProviderErrorKind.Timeout)
                throw new NormalizedProviderException(errorKind, "Simulated timeout failure");
            throw new NormalizedProviderException(errorKind, "Simulated quota failure");
        }
    }

    private sealed record CoverageReport(int Total, int Covered, IReadOnlyList<string> Missing);

    private sealed record PipelineDiagnostics(
        string Provider,
        string Model,
        int Attempt,
        string? RequestId,
        int CoveredRequirements,
        int TotalRequirements)
    {
        public bool IsComplete => TotalRequirements > 0 && CoveredRequirements == TotalRequirements;
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private static void AssertThrows<TException>(Action action, string message)
        where TException : Exception
    {
        try
        {
            action();
        }
        catch (TException)
        {
            return;
        }

        throw new InvalidOperationException(message);
    }

    private static async Task AssertThrowsAsync<TException>(Func<Task> action, string message)
        where TException : Exception
    {
        try
        {
            await action();
        }
        catch (TException)
        {
            return;
        }

        throw new InvalidOperationException(message);
    }
}
