using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

// 32-bit DLL injector: CreateProcess(SUSPENDED) -> inject LoadLibraryW -> resume.
// Usage: injector.exe <dllPath> <exePath> [args...]
class Injector
{
    const uint CREATE_SUSPENDED = 0x00000004;
    const uint PROCESS_ALL_ACCESS = 0x001F0FFF;
    const uint MEM_COMMIT = 0x1000;
    const uint MEM_RESERVE = 0x2000;
    const uint PAGE_READWRITE = 0x04;
    const uint INFINITE = 0xFFFFFFFF;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO
    {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION
    {
        public IntPtr hProcess, hThread;
        public int dwProcessId, dwThreadId;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(string app, string cmd, IntPtr pa, IntPtr ta, bool inherit,
        uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr addr, uint size, uint type, uint protect);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool WriteProcessMemory(IntPtr h, IntPtr addr, byte[] buf, uint size, out UIntPtr written);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Ansi)]
    static extern IntPtr GetProcAddress(IntPtr module, string proc);
    [DllImport("kernel32.dll")]
    static extern IntPtr GetModuleHandleW(string name);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr CreateRemoteThread(IntPtr h, IntPtr sa, uint stack, IntPtr start, IntPtr param, uint flags, out uint tid);
    [DllImport("kernel32.dll")]
    static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll")]
    static extern uint ResumeThread(IntPtr h);
    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")]
    static extern bool TerminateProcess(IntPtr h, uint code);
    [DllImport("kernel32.dll")]
    static extern uint GetLastError();

    static int Main(string[] args)
    {
        if (args.Length < 2)
        {
            Console.WriteLine("usage: injector.exe <dllPath> <exePath> [args...]");
            return 2;
        }
        string dll = System.IO.Path.GetFullPath(args[0]);
        string exe = System.IO.Path.GetFullPath(args[1]);
        string cwd = System.IO.Path.GetDirectoryName(exe);
        StringBuilder cmd = new StringBuilder();
        cmd.Append('"').Append(exe).Append('"');
        for (int i = 2; i < args.Length; i++) cmd.Append(' ').Append(args[i]);
        Console.WriteLine("exe: " + exe);
        Console.WriteLine("cwd: " + cwd);
        Console.WriteLine("cmd: " + cmd);
        Console.WriteLine("dll: " + dll);

        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        PROCESS_INFORMATION pi;
        if (!CreateProcessW(exe, cmd.ToString(), IntPtr.Zero, IntPtr.Zero, false,
            CREATE_SUSPENDED, IntPtr.Zero, cwd, ref si, out pi))
        {
            Console.WriteLine("CreateProcess failed: " + GetLastError());
            return 3;
        }
        Console.WriteLine("pid=" + pi.dwProcessId);

        byte[] bytes = Encoding.Unicode.GetBytes(dll + "\0");
        IntPtr mem = VirtualAllocEx(pi.hProcess, IntPtr.Zero, (uint)bytes.Length, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
        if (mem == IntPtr.Zero) { Console.WriteLine("VirtualAllocEx failed: " + GetLastError()); return 4; }
        UIntPtr written;
        if (!WriteProcessMemory(pi.hProcess, mem, bytes, (uint)bytes.Length, out written))
        {
            Console.WriteLine("WriteProcessMemory failed: " + GetLastError());
            return 5;
        }
        IntPtr loadLibrary = GetProcAddress(GetModuleHandleW("kernel32.dll"), "LoadLibraryW");
        uint tid;
        IntPtr thread = CreateRemoteThread(pi.hProcess, IntPtr.Zero, 0, loadLibrary, mem, 0, out tid);
        if (thread == IntPtr.Zero) { Console.WriteLine("CreateRemoteThread failed: " + GetLastError()); return 6; }
        Console.WriteLine("inject thread wait: " + WaitForSingleObject(thread, 10000));
        CloseHandle(thread);
        uint resume = ResumeThread(pi.hThread);
        Console.WriteLine("ResumeThread: " + resume);
        CloseHandle(pi.hThread);
        Console.WriteLine("OK pid=" + pi.dwProcessId);
        return 0;
    }
}
