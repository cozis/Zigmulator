
# Deterministic Simulation Testing

Deterministic Simulation Testing consists of running a program in an environment that is completely controlled to exercise all its behaviors that would otherwise hard to reach. This allows running programs in scenarios that are much more hostile than production. This can be done deterministically or not. What makes determinism so great, is that any time a bug presents itself, it's possible to replay the scenarios that caused it. This is great because it's not always trivial to understand the causes of a bug from its symptoms.

By running a program inside a "simulation", we mean that any time the program interacts with the outside world (the disk, network, reads the time) we should be able to arbitrarily decide what is returned to the program. This allows us to test all the complex corser-cases that would otherwise hardly happen while testing. For instance we could decide to flip a bit in a file to see whether checksums are implemented correctly. This can be called Simulation Testing, which may be deterministic but usually isn't.

For instance say you want to test a program that uses the file system. You may test it by creating a wrapper over the file system calls to return random errors 10% of the time and call the real system the remaining 90%. This would be a non-deterministic approach since the kernel is not deterministic. If instead we created a mock of the file system that runs in memory and doesn't go through the kernel, that would make this approach deterministic, although it would be so only regarding file operations and not other things such network and time.

To achieve true determinism it's necessary to control all interactions with kernel and hardware. This includes intercepting any system calls or interactions with the hardware that would bypass the kernel (such as reading the CPU's timestamp counter). The other cause of non-determinism is scheduling. If our program uses threads or multiple processes that interact with each other, multiple runs of the program will produce different interleavings of those flows of execution, leading to differences in the output.

Overall, the main challenges of DST are
1. Mocking the world accurately
2. Controlling the scheduling

Unfortunately there is no silver bullet here. There are a number of solutions that make more or less sense given the specific situation.

Two notable examples of DST are TigerBeetle and Antithesis.

## DST in TigerBeetle

TigerBeetle is an open-source database for online transaction processing designed to be incredibly scalable and robust. The way it emplyes DST is by wrapping any interaction with the system with functions that may be switched with a mocked version.

The "mock the world" problem is solved by (1) only mocking the specific I/O operations needed by the system and (2) by not mocking system calls but their own I/O library with a simplified contract that is easier to reason about since less general.

TiberBeetle is replicated, which means a single instance of the database has multiple nodes, while each node is single-threaded. The interleaving of nodes is controlled by running all nodes in a single process and scheduling them in userspace.

The downside of this approach is that it's tailored to the application. The testing framework used by TigerBeetle can only be used for TigerBeetle or very similar applications, which means that with this approach the tested application is better be worth the work to mock the world.

## DST in Antithesis

Another interesting application of DST is that offered by Antithesis.

They decided to fix the mocking and scheduling problems in one swoop by making existing kernels determministic. Once you have a deterministic kernel, you can run and application on it unmodified, and the output will be completely predictable. Once you have a deterministic system, you can intercept system calls at runtime and inject arbitrary fauls.

This system is proprietary, so my understanding of it is based on what they made public. But my understanding is that they implemented a deterministic machine (as an hypervisor) that is deterministic, to then run the kernel on top of it. Since the underlying machine is deterministic, the kernel will be too.

The advantage of this approach is huge. You can perform DST on any program unmodified. The downside is creating a deterministic hypervisor, which requires a lot of work.

# How to Find Bugs

Okay so let's say you managed to set up a DST framework with fault injection. Now how do you find all the bugs?

Some bugs will merely present themselves by causing the program to crash. Some bugs will cause an unrecoverable state like requesting the value from an unmapped page or dividing by zero. This may be cause by the bug directly, or downstream of its effects: the bug will cause the program to run in an incoherent state until a hard stop condition is created. The way I visualize this is by throwing a fish net over a river. To catch a fish, you don't have to throw the net on the fish, you can instead throw the net side to side over the river and wait for the fish to reach the net.

A second class of bugs don't cause the program to crash but cause it to behave incorrectly and output an incorrect value. If the program is behaving incorrectly, it must mean that one or more invariants of its state have been violated. We can cause artificial crashes when such events occur via assertions. This effectively turns such bugs in the first kind of bugs.

The problem then becomes which invariants to check.
