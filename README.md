# zemporal
An async function scheduling system in Zig

To make "functions as values" work in Zig, we:
1) create a single type interface for the user-supplied function:
```zig
*const fn (*Task) void
```
2) rather than passing args through function params and returns, have users store their relevant data in a container struct
3) match the `*const fn (*Task) void` signature with a static function within that struct. this is the callable when it's time to run the function.
4) seemingly the hackiest part, use self = @fieldParentPtr to basically hack that static function into a method, so you can use the struct's arbitrary data as if they were args

This leans heavily on King Protty's Thread Pool implementation
https://zig.news/kprotty/resource-efficient-thread-pools-with-zig-3291
