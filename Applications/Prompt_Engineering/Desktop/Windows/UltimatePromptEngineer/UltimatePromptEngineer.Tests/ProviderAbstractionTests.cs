using UltimatePromptEngineer;

namespace UltimatePromptEngineer.Tests;

public static class ProviderAbstractionTests
{
    public static async Task RunAsync()
    {
        var localProvider = new LocalPromptProvider();
        Assert(!localProvider.RequiresCredential, "Local provider must not require a credential.");

        try
        {
            await new GeminiEnhancer().GenerateAsync(new PromptProviderRequest("context"));
        }
        catch (NormalizedProviderException ex)
        {
            Assert(ex.Kind == ProviderErrorKind.Authentication,
                "A missing remote key must expose an authentication diagnostic.");
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException(
                "The remote provider must reject a missing key with a normalized exception.",
                ex);
        }

        var fake = new DeterministicFakeProvider();
        var router = new PromptProviderRouter(new IPromptProvider[] { localProvider, fake });
        Assert(ReferenceEquals(router.Select(PromptProviderKind.Remote), fake), "Router must select the registered provider.");
        var result = await router.GenerateAsync(PromptProviderKind.Remote, new PromptProviderRequest("context"));
        Assert(result.UltimatePrompt == "fake:context", "Fake provider output must be deterministic.");
        Assert(fake.Calls == 1, "Provider must be invoked exactly once.");

        using var canceled = new CancellationTokenSource();
        canceled.Cancel();
        await AssertThrowsAsync<OperationCanceledException>(
            () => localProvider.GenerateAsync(new PromptProviderRequest("ignored"), canceled.Token),
            "Cancellation must cross the provider boundary.");
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
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

    private sealed class DeterministicFakeProvider : IPromptProvider
    {
        public int Calls { get; private set; }
        public PromptProviderKind Kind => PromptProviderKind.Remote;
        public string Name => "Deterministic fake";
        public string Model => "fake-v1";
        public bool RequiresCredential => false;

        public Task<PromptProviderResponse> GenerateAsync(PromptProviderRequest request, CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Calls++;
            return Task.FromResult(new PromptProviderResponse(Name, Model, $"fake:{request.CapturedContext}"));
        }
    }
}
