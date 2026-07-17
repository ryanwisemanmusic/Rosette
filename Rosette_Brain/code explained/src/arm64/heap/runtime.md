We need to take care of logging events as they occur in the heap, since this is a crucial thing to log once we record activity in the heap, since it is optional whether or not we send data to it it.

Everytime an event happens, we need to fetch data about it. This is so that if any critical issues pop up, it's very easy to log this. Here is what we need to keep track of:
```runtime.zig
event.heap_handle = heap_handle;

event.address = address;

event.size = size;

event.flags = flags;

event.result = result;

bridge.reportHeapEvent(event, noopContext);
```

The aim of looking into the heap is valuable when something goes wrong, and then we can check any data on what fails