using System.Text;

namespace UltimatePromptEngineer;

public sealed record ImportedPromptText(string FullPath, string FileName, string Text, Encoding Encoding);

public sealed class PromptFileSafety
{
    public const long DefaultMaximumBytes = 10 * 1024 * 1024;
    private static readonly HashSet<string> SupportedExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".txt", ".md", ".markdown", ".csv", ".json", ".xml", ".yaml", ".yml", ".log"
    };
    private static readonly HashSet<string> ReservedDeviceNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
    };

    private readonly long _maximumBytes;

    public PromptFileSafety(long maximumBytes = DefaultMaximumBytes)
    {
        if (maximumBytes <= 0) throw new ArgumentOutOfRangeException(nameof(maximumBytes));
        _maximumBytes = maximumBytes;
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
    }

    public string SupportedFileFilter =>
        "Supported text and document files (*.txt;*.md;*.markdown;*.csv;*.json;*.xml;*.yaml;*.yml;*.log)|*.txt;*.md;*.markdown;*.csv;*.json;*.xml;*.yaml;*.yml;*.log|All files (*.*)|*.*";

    public ImportedPromptText Import(string path)
    {
        try
        {
            var fullPath = ValidateExistingPath(path);
            var bytes = ReadBoundedBytes(fullPath);
            var (text, encoding) = Decode(bytes);
            return new ImportedPromptText(fullPath, Path.GetFileName(fullPath), text, encoding);
        }
        catch (UnauthorizedAccessException)
        {
            throw new PromptFileSafetyException("The selected file cannot be read with the current permissions.");
        }
        catch (IOException)
        {
            throw new PromptFileSafetyException("The selected file could not be read. Choose another local file.");
        }
        catch (ArgumentException)
        {
            throw new PromptFileSafetyException("The selected file path is invalid. Choose another local file.");
        }
        catch (NotSupportedException)
        {
            throw new PromptFileSafetyException("The selected file path is not supported.");
        }
    }

    public string Export(string directory, string requestedFileName, string content)
    {
        ArgumentNullException.ThrowIfNull(content);
        try
        {
            var fullDirectory = ValidateDirectory(directory);
            var safeName = SanitizeFileName(requestedFileName);
            var destination = Path.Combine(fullDirectory, safeName);
            return WriteNewFile(destination, content);
        }
        catch (UnauthorizedAccessException)
        {
            throw new PromptFileSafetyException("The export folder is not writable. Choose another local folder.");
        }
        catch (IOException)
        {
            throw new PromptFileSafetyException("The prompt could not be exported. Choose another local folder or filename.");
        }
        catch (ArgumentException)
        {
            throw new PromptFileSafetyException("The export path is invalid. Choose another local folder or filename.");
        }
        catch (NotSupportedException)
        {
            throw new PromptFileSafetyException("The export path is not supported.");
        }
    }

    public static string SanitizeFileName(string? requestedFileName)
    {
        var name = Path.GetFileName(requestedFileName ?? string.Empty);
        foreach (var invalid in Path.GetInvalidFileNameChars()) name = name.Replace(invalid, '_');
        name = name.Trim().Trim('.');
        if (string.IsNullOrWhiteSpace(name) || name is "." or "..") name = "ultimate-prompt.txt";
        if (!Path.HasExtension(name)) name += ".txt";
        if (ReservedDeviceNames.Contains(Path.GetFileNameWithoutExtension(name))) name = "ultimate-prompt.txt";
        return name;
    }

    private static string ValidateDirectory(string directory)
    {
        if (string.IsNullOrWhiteSpace(directory)) throw new PromptFileSafetyException("Choose an export folder.");
        var fullDirectory = Path.GetFullPath(directory);
        if (!Directory.Exists(fullDirectory)) throw new PromptFileSafetyException("The export folder does not exist.");
        return fullDirectory;
    }

    private static string ValidateExistingPath(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) throw new PromptFileSafetyException("Choose a file to import.");
        var fullPath = Path.GetFullPath(path);
        if (!SupportedExtensions.Contains(Path.GetExtension(fullPath)))
            throw new PromptFileSafetyException("Unsupported file type. Choose a text or document-like file.");
        if (!File.Exists(fullPath)) throw new PromptFileSafetyException("The selected file does not exist.");
        return fullPath;
    }

    private static string WriteNewFile(string destination, string content)
    {
        var directory = Path.GetDirectoryName(destination)!;
        var stem = Path.GetFileNameWithoutExtension(destination);
        var extension = Path.GetExtension(destination);
        for (var index = 1; index < int.MaxValue; index++)
        {
            var candidate = index == 1
                ? destination
                : Path.Combine(directory, $"{stem} ({index}){extension}");
            try
            {
                using var stream = new FileStream(candidate, FileMode.CreateNew, FileAccess.Write, FileShare.None);
                using var writer = new StreamWriter(stream, new UTF8Encoding(true));
                writer.Write(content);
                return candidate;
            }
            catch (IOException) when (File.Exists(candidate))
            {
                // The name was claimed after this attempt started; reserve the next suffix instead.
            }
        }
        throw new PromptFileSafetyException("Could not find an unused export filename.");
    }

    private byte[] ReadBoundedBytes(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        using var output = new MemoryStream();
        var buffer = new byte[81920];
        long total = 0;
        int read;
        while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
        {
            if (total > _maximumBytes - read)
                throw new PromptFileSafetyException($"The selected file is too large. Maximum size is {_maximumBytes:N0} bytes.");
            output.Write(buffer, 0, read);
            total += read;
        }

        return output.ToArray();
    }

    private static (string Text, Encoding Encoding) Decode(byte[] bytes)
    {
        if (bytes.AsSpan().StartsWith(new byte[] { 0xEF, 0xBB, 0xBF }))
            return (new UTF8Encoding(false, true).GetString(bytes, 3, bytes.Length - 3), new UTF8Encoding(false));
        if (bytes.AsSpan().StartsWith(new byte[] { 0xFF, 0xFE }))
            return (Encoding.Unicode.GetString(bytes, 2, bytes.Length - 2), Encoding.Unicode);
        if (bytes.AsSpan().StartsWith(new byte[] { 0xFE, 0xFF }))
            return (Encoding.BigEndianUnicode.GetString(bytes, 2, bytes.Length - 2), Encoding.BigEndianUnicode);
        try
        {
            return (new UTF8Encoding(false, true).GetString(bytes), new UTF8Encoding(false));
        }
        catch (DecoderFallbackException)
        {
            var fallback = Encoding.GetEncoding(1252);
            return (fallback.GetString(bytes), fallback);
        }
    }
}

public sealed class PromptFileSafetyException(string message) : InvalidOperationException(message);
