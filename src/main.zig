const std = @import("std");
const print = std.debug.print;

// Timeline is a single linked list, with soonest upcoming task at the head
const Timeline = struct {
    const Self = @This();

    // Tasks are heap allocated
    pub const Task = struct {
        startTime: i64,
        next: ?*Task = null,
        callback: *const fn (*Task) void, // we use containers to hold the implementaiton
    };

    head: ?*Task = null,
    alloc: std.mem.Allocator,
    mutex: std.Thread.Mutex = std.Thread.Mutex{},

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
                        continue;
                    }
                }
            }
            std.time.sleep(10);
        }
    }
};

const Context = struct {
    value: usize,
    task: Timeline.Task = .{ .callback = func, .startTime = 0 },

    pub fn scheduleToIncrement(this: *Context, tl: *Timeline, startTime: i64) !void {
        this.task.startTime = startTime;
        try tl.schedule(&this.task);
    }

    fn func(task_ptr: *Timeline.Task) void {
        print("Task triggered\n", .{});
        const this = @fieldParentPtr(Context, "task", task_ptr);
        this.value += 1;
    }
};

test "test" {
    var tl = Timeline{ .alloc = std.testing.allocator };
    defer tl.destroy();
    tl.debug();

    var c = Context{ .value = 1 };
    var now = std.time.milliTimestamp();
    print("c = {}\n", .{c.value});
    try c.scheduleToIncrement(&tl, now + 1000);
    tl.debug();
    print("c = {}\n", .{c.value});

    // run the engine in the background
    const t = try std.Thread.spawn(.{}, Timeline.run, .{&tl});
    defer t.join();

    for (0..20) |_| {
        print("c = {}\n", .{c.value});
        std.time.sleep(100_000_000);
    }
}
