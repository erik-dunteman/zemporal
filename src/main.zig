const std = @import("std");
const print = std.debug.print;

// Tasks are heap allocated
const Task = struct {
    startTime: i64,
    complete: bool = false,
    next: ?*Task = null,
    callback: *const fn (*Task) void, // we use context containers to hold the implementation, and just point to it here

    fn wait(self: *Task) void {
        while (!self.complete) {
            std.time.sleep(10);
        }
    }
};

// Timeline is a single linked list, with soonest upcoming task at the head
const Timeline = struct {
    const Self = @This();

    head: ?*Task = null,
    alloc: std.mem.Allocator,
    mutex: std.Thread.Mutex = std.Thread.Mutex{},
    closed: bool = false,

    fn close(self: *Self) void {
        self.closed = true;
    }

    fn debug(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        print("TL Debug: ", .{});
        if (self.head) |head| {
            print("{*}={d} ", .{ head, head.startTime });
            var node = head;
            while (node.next) |next| {
                node = next;
                print("{*}={d} ", .{ node, node.startTime });
            }
        }
        print("\n", .{});
    }

    fn destroy(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.head) |head| {
            var node = head;
            while (true) {
                const next = node.next;
                self.alloc.destroy(node);
                if (next) |nex| {
                    node = nex;
                } else break;
            }
        }
    }

    fn schedule(self: *Self, task: *Task) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        defer print("Task scheduled\n", .{});

        if (self.head) |head| {

            // case: new task should be first in timeline
            if (task.startTime < head.startTime) {
                task.next = head;
                self.head = task;
                return;
            }

            var node = head;
            var prevNode = node;
            // scan until we find a node scheduled after this task
            while (node.next) |next| {
                prevNode = node;
                node = next;
                if (node.startTime > task.startTime) {
                    prevNode.next = task;
                    task.next = node;
                    return;
                }
            }

            // if here, it's the EOL case
            node.next = task;
            return;
        } else {
            self.head = task;
            return;
        }
    }

    fn run(self: *Self) void {
        while (true) {
            // check first task in loop (it'll be the soonest)
            // if valid, pop it, print it, continue
            // else sleep
            {
                self.mutex.lock();
                defer self.mutex.unlock();
                if (self.head) |head| {
                    if (head.startTime < std.time.milliTimestamp()) {
                        print("Task triggered\n", .{});
                        self.head = head.next;
                        (head.callback)(head);
                        head.complete = true;
                        continue;
                    }
                }
            }
            // only in case of nothing to consume
            std.time.sleep(10);
            if (self.closed) {
                break;
            }
        }
    }
};

test "test" {
    // start the scheduling engine in the background
    var tl = Timeline{ .alloc = std.testing.allocator };
    defer tl.destroy();
    const t = try std.Thread.spawn(.{}, Timeline.run, .{&tl});
    defer t.join();

    // user-defined Context container containing callback func
    const Context = struct {
        task: Task,
        value: usize,

        const Self = @This();

        pub fn new(value: usize, startTime: i64) Self {
            return Self{
                .task = .{ .callback = func, .startTime = startTime },
                .value = value,
            };
        }

        // users must follow this boilerplate
        fn func(task_ptr: *Task) void {
            const this = @fieldParentPtr(Self, "task", task_ptr);

            // users implement arbitrary function here
            // for example, incrementing some value
            this.value += 1;
        }
    };

    // create task context
    // set contained value to 1. This is effectively the function argument.
    // set startTime to 2 seconds in future.
    var c = Context.new(1, std.time.milliTimestamp() + 2000);
    print("c = {}\n", .{c.value});
    try std.testing.expect(c.value == 1);

    // schedule
    try tl.schedule(&c.task);

    // await completion
    c.task.wait();
    print("c = {}\n", .{c.value});
    try std.testing.expect(c.value == 2);

    // cleanup
    tl.close();
}
