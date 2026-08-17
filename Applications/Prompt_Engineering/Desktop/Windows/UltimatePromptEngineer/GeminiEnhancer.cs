using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;

namespace UltimatePromptEngineer;

public sealed class GeminiCredentialException : Exception { }
public sealed class GeminiQuotaException : Exception { }

public sealed record ProviderResult(
    string Provider,
    string Model,
    int Attempt,
    bool UsedFallback,
    string Status,
    string? RequestId,
    string? ErrorCode,
    string UltimatePrompt);

public sealed class GeminiEnhancer : IPromptProvider
{
    public const string ModelId = "gemini-3.6-flash";

    private static readonly HttpClient Client = new() { Timeout = TimeSpan.FromSeconds(45) };

    public PromptProviderKind Kind => PromptProviderKind.Remote;
    public string Name => "Gemini Developer API";
    public string Model => ModelId;
    public bool RequiresCredential => true;

    public async Task<PromptProviderResponse> GenerateAsync(PromptProviderRequest request, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(request.Credential))
            throw new NormalizedProviderException(ProviderErrorKind.Authentication, "A remote provider credential is required.");

        try
        {
            var result = await EnhanceAsync(request.Credential, request.CapturedContext, cancellationToken);
            return new PromptProviderResponse(result.Provider, result.Model, result.UltimatePrompt, result.Attempt, result.RequestId);
        }
        catch (GeminiCredentialException ex)
        {
            throw new NormalizedProviderException(ProviderErrorKind.Authentication, "The remote provider rejected the credential.", ex);
        }
        catch (GeminiQuotaException ex)
        {
            throw new NormalizedProviderException(ProviderErrorKind.Quota, "The remote provider quota is unavailable.", ex);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new NormalizedProviderException(ProviderErrorKind.Timeout, "The remote provider request timed out.");
        }
        catch (OperationCanceledException ex)
        {
            throw new NormalizedProviderException(ProviderErrorKind.Cancellation, "The remote provider request was canceled.", ex);
        }
        catch (HttpRequestException ex)
        {
            throw new NormalizedProviderException(ProviderErrorKind.Unavailable, "The remote provider could not be reached.", ex);
        }
        catch (JsonException ex)
        {
            throw new NormalizedProviderException(ProviderErrorKind.InvalidResponse, "The remote provider returned an invalid response.", ex);
        }
        catch (InvalidOperationException ex)
        {
            throw new NormalizedProviderException(ProviderErrorKind.InvalidResponse, "The remote provider returned an unexpected response.", ex);
        }
    }

    public async Task<ProviderResult> EnhanceAsync(string apiKey, string capturedContext, CancellationToken cancellationToken = default)
    {
        for (var attempt = 1; attempt <= 2; attempt++)
        {
            try
            {
                return await SendOnceAsync(apiKey, capturedContext, attempt, cancellationToken);
            }
            catch (GeminiQuotaException) when (attempt == 1)
            {
                await Task.Delay(TimeSpan.FromSeconds(2), cancellationToken);
            }
            catch (HttpRequestException) when (attempt == 1)
            {
                await Task.Delay(TimeSpan.FromSeconds(1), cancellationToken);
            }
        }

        throw new HttpRequestException("Gemini was unavailable after the bounded retry.");
    }

    private static async Task<ProviderResult> SendOnceAsync(string apiKey, string capturedContext, int attempt, CancellationToken cancellationToken)
    {
        var endpoint = $"https://generativelanguage.googleapis.com/v1beta/models/{ModelId}:generateContent";
        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
        request.Headers.Add("x-goog-api-key", apiKey);
        request.Content = new StringContent(JsonSerializer.Serialize(new
        {
            systemInstruction = new
            {
                parts = new[]
                {
                    new
                    {
                        text = "You are the Ultimate Prompt Engineer. Convert every captured user-provided item into one complete, explicit, actionable prompt for an AI agent. Preserve all requirements and uncertainty; never discard information. Return JSON only."
                    }
                }
            },
            contents = new[]
            {
                new
                {
                    role = "user",
                    parts = new[] { new { text = capturedContext } }
                }
            },
            generationConfig = new
            {
                thinkingConfig = new { thinkingLevel = "high" },
                responseMimeType = "application/json",
                responseSchema = new Dictionary<string, object?>
                {
                    ["type"] = "object",
                    ["properties"] = new
                    {
                        ultimatePrompt = new { type = "string" },
                        assumptions = new { type = "array", items = new { type = "string" } },
                        openQuestions = new { type = "array", items = new { type = "string" } }
                    },
                    ["required"] = new[] { "ultimatePrompt" }
                },
                maxOutputTokens = 8192
            }
        }), Encoding.UTF8, "application/json");

        using var response = await Client.SendAsync(request, cancellationToken);
        var content = await response.Content.ReadAsStringAsync(cancellationToken);
        var requestId = response.Headers.TryGetValues("x-request-id", out var requestIds) ? requestIds.FirstOrDefault() : null;

        if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
        {
            throw new GeminiCredentialException();
        }

        if (response.StatusCode == HttpStatusCode.TooManyRequests)
        {
            throw new GeminiQuotaException();
        }

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"Gemini returned {(int)response.StatusCode}.");
        }

        using var document = JsonDocument.Parse(content);
        var modelText = document.RootElement
            .GetProperty("candidates")[0]
            .GetProperty("content")
            .GetProperty("parts")[0]
            .GetProperty("text")
            .GetString();

        if (string.IsNullOrWhiteSpace(modelText))
        {
            throw new HttpRequestException("Gemini returned an empty response.");
        }

        using var result = JsonDocument.Parse(modelText);
        if (!result.RootElement.TryGetProperty("ultimatePrompt", out var prompt))
        {
            throw new HttpRequestException("Gemini did not return an ultimatePrompt.");
        }

        return new ProviderResult("Gemini Developer API", ModelId, attempt, false, "success", requestId, null, prompt.GetString() ?? string.Empty);
    }
}
