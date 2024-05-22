const std = @import("std");
const print = std.debug.print;

// Tasks are heap allocated
const Task = struct {
    startTime: i64,
    complete: bool = false,
    next: ?*Task = null,
    callback: *const fn (*Task) void, // we use context containers to hold the implementation, and just point to it here
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

    // user-defined Context container containing callback func
    const Context = struct {
        value: usize,
        task: Task,

        const Self = @This();

        pub fn new(value: usize, startTime: i64) Self {
            return Self{
                .task = .{ .callback = func, .startTime = startTime },
                .value = value,
            };
        }

        fn func(task_ptr: *Task) void {
            print("Task triggered\n", .{});
            const this = @fieldParentPtr(Self, "task", task_ptr);
            this.value += 1;
        }
    };

    var tl = Timeline{ .alloc = std.testing.allocator };
    defer tl.destroy();
    tl.debug();

    var now = std.time.milliTimestamp();

    var c = Context.new(1, now + 1000);
    print("c = {}\n", .{c.value});
    try tl.schedule(&c.task);
    tl.debug();
    print("c = {}\n", .{c.value});

    // run the engine in the background
    const t = try std.Thread.spawn(.{}, Timeline.run, .{&tl});
    defer t.join();

    while (c.task.complete == false) {
        print("c = {}\n", .{c.value});
        std.time.sleep(100_000_000);
    }
    print("c = {}\n", .{c.value});

    tl.close();
}
