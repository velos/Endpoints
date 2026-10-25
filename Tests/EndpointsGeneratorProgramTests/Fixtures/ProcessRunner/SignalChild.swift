#if os(Linux)
import Glibc
#else
import Darwin
#endif

guard CommandLine.arguments.count == 2 else { exit(100) }
switch CommandLine.arguments[1] {
case "exit15": exit(15)
case "exit143": exit(143)
case "signal":
    // Linux dispatch workers block SIGTERM, and corelibs Process inherits that
    // mask. Do not rely on a shell's handling of inherited masks/dispositions.
    _ = signal(SIGTERM, SIG_DFL)
    var mask = sigset_t()
    guard sigemptyset(&mask) == 0, sigaddset(&mask, SIGTERM) == 0,
        // Exercise the unblock even on hosts that start with SIGTERM unblocked.
        sigprocmask(SIG_BLOCK, &mask, nil) == 0,
        sigprocmask(SIG_UNBLOCK, &mask, nil) == 0
    else { exit(101) }
    guard kill(getpid(), SIGTERM) == 0 else { exit(102) }
    exit(103) // Unreachable: the process must die by SIGTERM, not call exit.
default: exit(100)
}
