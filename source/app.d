import std.stdio;
import dind;
import std.getopt;
import std.functional;

int main(string[] args) {
  bool print = false;
  bool threads = false;
  auto helpInformation =
    getopt(args,
           "print|p", "print findings", &print,
           "threads|t", "use multithreaded walker", &threads
    );

  if (helpInformation.helpWanted) {
    defaultGetoptPrinter("finding files.",
                         helpInformation.options);
    return 0;
  }

  void printNothing(string f) {
  }

  string path = args.length > 1 ? args[1] : ".";
  void delegate(string) printer = print ? (f) => writeln(f) : &printNothing;

  if (threads) {
    writeln("using threads");
    dind.parallelDind(path, printer);
  } else {
    dind.dind(path, printer);
  }
  return 0;
}
