using System.IO;
using System.Text.RegularExpressions;

// 1. Get the commit message from the git args path
var commitMsgFile = Args[0];
var msg = File.ReadAllLines(commitMsgFile)[0];

// 2. Conventional Commit Regex pattern
var pattern = @"^(feat|fix|chore|docs|style|refactor|perf|test|build|revert)(\(.+\))?: .{1,90}$";

if (Regex.IsMatch(msg, pattern))
{
    return 0; // Success!
}

// 3. Print friendly error message if it fails
Console.ForegroundColor = ConsoleColor.Red;
Console.WriteLine("\nINVALID COMMIT MESSAGE");
Console.ResetColor();
Console.WriteLine("Your message: \"" + msg + "\"");
Console.WriteLine("Conventional commits format required: <type>(<scope>): <subject>");
Console.WriteLine("Allowed types: feat, fix, chore, docs, style, refactor, perf, test, build, revert");
Console.WriteLine("Example: chore: setup husky validation\n");

return 1; // Block the commit
