namespace UltimatePromptEngineer;

public enum PromptProviderKind { Local, Remote }

public enum ProviderErrorKind { Cancellation, Timeout, Authentication, Quota, Unavailable, InvalidResponse }

public sealed record PromptProviderRequest(string CapturedContext, string? Credential = null, TimeSpan? Timeout = null);

public sealed record PromptProviderResponse(string Provider, string Model, string UltimatePrompt, int Attempt = 1, string? RequestId = null);

public sealed class NormalizedProviderException : Exception
{
    public NormalizedProviderException(ProviderErrorKind kind, string message, Exception? inner = null) : base(message, inner) => Kind = kind;
    public ProviderErrorKind Kind { get; }
}

public interface IPromptProvider
{
    PromptProviderKind Kind { get; }
    string Name { get; }
    string Model { get; }
    bool RequiresCredential { get; }
    Task<PromptProviderResponse> GenerateAsync(PromptProviderRequest request, CancellationToken cancellationToken = default);
}

public sealed class LocalPromptProvider : IPromptProvider
{
    public PromptProviderKind Kind => PromptProviderKind.Local;
    public string Name => "Local template";
    public string Model => "local-template-v1";
    public bool RequiresCredential => false;

    public Task<PromptProviderResponse> GenerateAsync(PromptProviderRequest request, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(new PromptProviderResponse(Name, Model, request.CapturedContext));
    }
}

public sealed class PromptProviderRouter
{
    private readonly IReadOnlyDictionary<PromptProviderKind, IPromptProvider> _providers;

    public PromptProviderRouter(IEnumerable<IPromptProvider> providers) => _providers = providers.ToDictionary(p => p.Kind);

    public IPromptProvider Select(PromptProviderKind kind) =>
        _providers.TryGetValue(kind, out var provider)
            ? provider
            : throw new ArgumentOutOfRangeException(nameof(kind), kind, "Provider is not registered.");

    public Task<PromptProviderResponse> GenerateAsync(PromptProviderKind kind, PromptProviderRequest request, CancellationToken cancellationToken = default) =>
        Select(kind).GenerateAsync(request, cancellationToken);
}
