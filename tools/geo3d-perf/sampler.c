// LD_PRELOAD sampling profiler: records the program counter every 1 ms of CPU time.
#define _GNU_SOURCE
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <ucontext.h>

#define MAX_SAMPLES (4u << 20)
static unsigned long* samples;
static volatile unsigned long count;

static void on_prof(int sig, siginfo_t* info, void* ctx)
{
	(void)sig; (void)info;
	ucontext_t* u = (ucontext_t*)ctx;
	unsigned long i = count;
	if (i < MAX_SAMPLES) {
		samples[i] = (unsigned long)u->uc_mcontext.gregs[REG_RIP];
		count = i + 1;
	}
}

static void dump(void)
{
	const char* out = getenv("PROF_OUT");
	if (!out || !samples) return;
	struct itimerval off;
	memset(&off, 0, sizeof(off));
	setitimer(ITIMER_PROF, &off, NULL);
	FILE* f = fopen(out, "w");
	if (!f) return;
	FILE* m = fopen("/proc/self/maps", "r");
	char line[1024];
	while (m && fgets(line, sizeof(line), m)) fprintf(f, "M %s", line);
	if (m) fclose(m);
	for (unsigned long i = 0; i < count; ++i) fprintf(f, "S %lx\n", samples[i]);
	fclose(f);
	samples = NULL;
}

__attribute__((constructor)) static void init(void)
{
	if (!getenv("PROF_OUT")) return;
	// env and taskset inherit LD_PRELOAD too: an interval timer survives exec but the
	// handler does not, so arming it there would kill the real target.
	extern char* program_invocation_short_name;
	if (strcmp(program_invocation_short_name, "openmsx") != 0) return;
	samples = malloc(sizeof(unsigned long) * MAX_SAMPLES);
	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_sigaction = on_prof;
	sa.sa_flags = SA_SIGINFO | SA_RESTART;
	sigaction(SIGPROF, &sa, NULL);
	struct itimerval it;
	it.it_interval.tv_sec = 0; it.it_interval.tv_usec = 1000;
	it.it_value = it.it_interval;
	setitimer(ITIMER_PROF, &it, NULL);
	atexit(dump);
}
