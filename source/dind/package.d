module dind;
import core.cpuid;
import std.file;
import std.stdio;
import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.errno;
import core.sys.posix.dirent;
import std.internal.cstring;
import std.string;
import std.conv;
import std.range;
import std.parallelism;
import std.concurrency;

string cstr2string(char* cstr) {
  immutable len = core.stdc.string.strlen(cstr);
  return to!string(cstr[0..len]);
}

bool isDot(T)(T name) {
  return
    (name[0] != 0) &&
    (name[1] == 0) &&
    (name[0] == '.');
}

bool isDotDot(T)(T name) {
  return
    (name[0] != 0) &&
    (name[1] != 0) &&
    (name[2] == 0) &&
    (name[0] == '.') &&
    (name[1] == '.');
}

void dind(string path, void delegate(string) report) {
  auto d = opendir(path.tempCString());
  scope(exit) closedir(d);

  auto dirent = readdir(d);
  while (dirent) {
    if (!(isDot(dirent.d_name) || isDotDot(dirent.d_name))) {
      string newPath = path ~ "/" ~ cstr2string(dirent.d_name.ptr);
      report(newPath);
      if (dirent.d_type == DT_DIR) {
        dind(newPath, report);
      }
    }
    dirent = readdir(d);
  }
}

struct AddWork {
  string payload;
}
struct Reschedule{}
struct Shutdown{}
struct WorkFinished{}
void scheduler(void delegate(string) report) {
  /// keeps track of jobs todo
  string[] pendingJobs;
  /// the workers that are not busy
  Tid[] idleWorkers;
  /// number of busy workers
  int busyWorkerCount;
  /// are we finished
  bool finished = false;
  while (!finished) {
    receive(
      (AddWork work) {
        pendingJobs ~= work.payload;
        thisTid.send(Reschedule());
      },
      (Tid worker, WorkFinished f) {
        busyWorkerCount = busyWorkerCount-1;
        idleWorkers ~= worker;
        thisTid.send(Reschedule());
      },
      (Tid worker) {
        idleWorkers ~= worker;
        thisTid.send(Reschedule());
      },
      (Reschedule r) {
        if (pendingJobs.empty()) {
          if (busyWorkerCount == 0) {
            foreach (worker; idleWorkers) {
              worker.send(Shutdown());
            }
            finished = true;
          }
        } else {
          if (!idleWorkers.empty) {
            auto worker = idleWorkers.front; idleWorkers.popFront;
            auto work = pendingJobs.front; pendingJobs.popFront;
            busyWorkerCount++;
            worker.send(work);
            thisTid.send(Reschedule());
          }
        }
      }
    );
  }
}

void parallelDindFunction(Tid s, void delegate(string) report) {
  bool finished = false;
  s.send(thisTid());
  while (!finished) {
    receive(
      (Shutdown s) {
        finished = true;
      },
      (string path) {
        auto d = opendir(path.tempCString());
        scope(exit) closedir(d);

        auto dirent = readdir(d);
        while (dirent) {
          if (!(isDot(dirent.d_name) || isDotDot(dirent.d_name))) {
            string newPath = path ~ "/" ~ cstr2string(dirent.d_name.ptr);
            report(newPath);
            if (dirent.d_type == DT_DIR) {
              s.send(AddWork(newPath));
            }
          }
          dirent = readdir(d);
        }
        s.send(thisTid, WorkFinished());
      }
    );
  }
}

void parallelDind(string path, void delegate(string) report) {
  auto s = spawnLinked(&scheduler, cast(shared)report);
  s.send(AddWork(path));
  int nrOfWorkers = totalCPUs;
  for (int i=0; i<nrOfWorkers; ++i) {
    s.send(spawnLinked(&parallelDindFunction, s, cast(shared)report));
  }

  for (int i=0; i<nrOfWorkers+1; i++) {
    receiveOnly!LinkTerminated;
  }
}