namespace UltimatePromptEngineer;

public enum PromptIntent
{
    BuildOrImplement,
    AnalyzeOrResearch,
    WriteOrRewrite,
    DebugOrReview,
    PlanATask
}

public enum PromptAudience
{
    AnyAiAgent,
    CodingAgent,
    ResearchAgent,
    WritingAgent
}

public enum PromptStrategy
{
    PreserveAndDeliver,
    PlanAndExecute,
    DiagnoseAndFix,
    RewriteWithConstraints,
    ResearchAndCompare
}

public sealed record PromptSpecification(
    string RawRequest,
    PromptIntent Intent,
    PromptAudience Audience,
    bool AddChecklist,
    PromptStrategy Strategy = PromptStrategy.PreserveAndDeliver,
    string Requirements = "");

public interface IPromptClassifier
{
    PromptIntent ClassifyIntent(string intent);

    PromptAudience ClassifyAudience(string audience);

    PromptStrategy ClassifyStrategy(string strategy);
}

public sealed class PromptClassifier : IPromptClassifier
{
    public PromptIntent ClassifyIntent(string intent) => intent switch
    {
        "Build or implement" => PromptIntent.BuildOrImplement,
        "Analyze or research" => PromptIntent.AnalyzeOrResearch,
        "Write or rewrite" => PromptIntent.WriteOrRewrite,
        "Debug or review" => PromptIntent.DebugOrReview,
        "Plan a task" => PromptIntent.PlanATask,
        _ => throw new ArgumentOutOfRangeException(nameof(intent), intent, "Unknown prompt intent.")
    };

    public PromptAudience ClassifyAudience(string audience) => audience switch
    {
        "Any AI agent" => PromptAudience.AnyAiAgent,
        "Coding agent" => PromptAudience.CodingAgent,
        "Research agent" => PromptAudience.ResearchAgent,
        "Writing agent" => PromptAudience.WritingAgent,
        _ => throw new ArgumentOutOfRangeException(nameof(audience), audience, "Unknown prompt audience.")
    };

    public PromptStrategy ClassifyStrategy(string strategy) => strategy switch
    {
        "Preserve and deliver" => PromptStrategy.PreserveAndDeliver,
        "Plan and execute" => PromptStrategy.PlanAndExecute,
        "Diagnose and fix" => PromptStrategy.DiagnoseAndFix,
        "Rewrite with constraints" => PromptStrategy.RewriteWithConstraints,
        "Research and compare" => PromptStrategy.ResearchAndCompare,
        _ => throw new ArgumentOutOfRangeException(nameof(strategy), strategy, "Unknown prompt strategy.")
    };
}

public static class PromptSpecificationText
{
    public static string Intent(PromptIntent intent) => intent switch
    {
        PromptIntent.BuildOrImplement => "Build or implement",
        PromptIntent.AnalyzeOrResearch => "Analyze or research",
        PromptIntent.WriteOrRewrite => "Write or rewrite",
        PromptIntent.DebugOrReview => "Debug or review",
        PromptIntent.PlanATask => "Plan a task",
        _ => throw new ArgumentOutOfRangeException(nameof(intent), intent, "Unknown prompt intent.")
    };

    public static string Audience(PromptAudience audience) => audience switch
    {
        PromptAudience.AnyAiAgent => "Any AI agent",
        PromptAudience.CodingAgent => "Coding agent",
        PromptAudience.ResearchAgent => "Research agent",
        PromptAudience.WritingAgent => "Writing agent",
        _ => throw new ArgumentOutOfRangeException(nameof(audience), audience, "Unknown prompt audience.")
    };

    public static string Strategy(PromptStrategy strategy) => strategy switch
    {
        PromptStrategy.PreserveAndDeliver => "Preserve and deliver",
        PromptStrategy.PlanAndExecute => "Plan and execute",
        PromptStrategy.DiagnoseAndFix => "Diagnose and fix",
        PromptStrategy.RewriteWithConstraints => "Rewrite with constraints",
        PromptStrategy.ResearchAndCompare => "Research and compare",
        _ => throw new ArgumentOutOfRangeException(nameof(strategy), strategy, "Unknown prompt strategy.")
    };
}
