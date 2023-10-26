const std = @import("std");
const win = std.os.windows;
const WINAPI = win.WINAPI;
const DELTA_THRESHOLD = 48;
pub fn main() void {    
    const wnd_class = RegisterClassA(
        &WNDCLASSA {
            .lpfnWndProc = wndProc,
            .lpszClassName = "window",
        }
    );
    const hwnd = CreateWindowExA(
        0,
        @ptrFromInt(@as(usize,@intCast(wnd_class))),
        "",
        0,
        0,0,0,0,
        @ptrFromInt(@as(usize,@bitCast(@as(isize,-3)))),
        null,
        null, 
        null
    );
    if (0==RAWINPUTDEVICE.register(0xD,0x5,0x100,hwnd)) return;
    var msg: MSG = undefined;
    while(GetMessageA(&msg,null,0,0)>0) {
        _ = DispatchMessageA(&msg);
    }
}

fn wndProc(hwnd: HWND, uMsg: u32, wParam: usize, lParam: isize) callconv(WINAPI) isize {
    if (0x00ff==uMsg) {
        var data: RAWINPUT.HID(30) = undefined;
        if (0<data.getData(lParam)) processInput(&data);
    }
    return DefWindowProcA(hwnd,uMsg,wParam,lParam);
}

fn processInput(data: *RAWINPUT.HID(30)) void {
    const static = opaque {
        var hold = true;
        var last_counts = @as(u8,0);
        var last_center = @Vector(2,f32){0,0};
        var accumulator = @Vector(2,f32){0,0};
        var residual    = @Vector(2,f32){0,0};
    };
    const PTPData = packed struct {
        _1: u8,
        f1: u8, x1: u16, y1: u16,
        f2: u8, x2: u16, y2: u16,
        f3: u8, x3: u16, y3: u16,
        f4: u8, x4: u16, y4: u16,
        f5: u8, x5: u16, y5: u16,
        time: u16,
        contacts: u8,
        click: u8,
    };

    const fingers: *PTPData = @ptrCast(&data.data.bRawData);
    const norm: f32 = @floatFromInt(fingers.contacts);
    const xSum: f32 = @floatFromInt(fingers.x1 + fingers.x2 + fingers.x3 + fingers.x4 + fingers.x5);
    const ySum: f32 = @floatFromInt(fingers.y1 + fingers.y2 + fingers.y3 + fingers.y4 + fingers.y5);
    const center: @Vector(2,f32) = if (norm>0) .{xSum/norm, ySum/norm} else .{0,0};
    if (static.last_counts==3) {
        if (fingers.contacts==3) {
            const delta = center - static.last_center;
            if (static.hold) {
                static.accumulator += delta;
                if (@reduce(.Add,static.accumulator*static.accumulator) > DELTA_THRESHOLD*DELTA_THRESHOLD) {
                    static.hold = false;
                    static.accumulator = .{0,0};
                    _ = mb1(true);
                }
            } else if (@reduce(.Add,delta*delta)>0) {
                const target = delta + static.residual;
                const actual = @trunc(target);
                static.residual = target - actual;
                _ = move(@intFromFloat(actual[0]),@intFromFloat(actual[1]));
            }
        } else {
            static.hold = true;
            _ = mb1(false);
        }
    }
    static.last_counts = fingers.contacts;
    static.last_center = center;
}

fn move(x:i32, y:i32) u32 {
    return (INPUT {
        .type = 0,
        .input = .{
            .mi = .{
                .dx = x,
                .dy = y,
                .dwFlags = 0x0001,
            },
        },
    }).send();
}

fn mb1(state: bool) u32 {
    return (INPUT {
        .type = 0,
        .input = .{
            .mi = .{
                .dwFlags = if (state) 0x0002 else 0x0004,
            },
        },
    }).send();
}

extern "user32" fn RegisterClassA(*const WNDCLASSA) callconv(WINAPI) u16;
extern "user32" fn DefWindowProcA(HWND, u32, usize, isize) callconv(WINAPI) isize;
extern "user32" fn CreateWindowExA(u32, *anyopaque, [*:0]const u8, u32, i32, i32, i32, i32, ?HWND, ?*const anyopaque, ?HINSTANCE, ?*const anyopaque) callconv(WINAPI) ?HWND;
extern "user32" fn PostQuitMessage(i32) callconv(WINAPI) void;
extern "user32" fn GetMessageA(*MSG, ?HWND, u32, u32) callconv(WINAPI) i32;
extern "user32" fn DispatchMessageA(*const MSG) callconv(WINAPI) isize;

const HWND = *opaque{};
const HINSTANCE = *opaque{};
const WNDPROC = *const fn (HWND, u32, usize, isize) callconv(WINAPI) isize;
const WNDCLASSA = extern struct {
    style: u32 = 0,
    lpfnWndProc: WNDPROC,
    cbClsExtra: i32 = 0,
    cbWndExtr: i32 = 0,
    hInstance:     ?HINSTANCE = null,
    hIcon:         ?*opaque{} = null,
    hCursor:       ?*opaque{} = null,
    hbrBackground: ?*opaque{} = null,
    lpszMenuName: ?*anyopaque = null,
    lpszClassName: *const anyopaque,
};

const MSG = extern struct {
    hWnd: ?HWND,
    message: u32,
    wParam: usize,
    lParam: isize,
    time: u32,
    pt: extern struct {
        x: i32,
        y: i32,
    },
    lPrivate: u32,
};

const RAWINPUTDEVICE = extern struct {
    usUsagePage : u16,
    usUsage : u16,
    dwFlags : u32,
    hwndTarget : ?HWND,    
    extern "user32" fn RegisterRawInputDevices([*]const RAWINPUTDEVICE,u32,u32) i32;
    pub fn register(page:u16,usage:u16,flags:u32,target:?HWND) i32 {
        return RegisterRawInputDevices(
            @ptrCast(&RAWINPUTDEVICE{
                .usUsagePage = page,
                .usUsage = usage,
                .dwFlags = flags,
                .hwndTarget = target,
            }),1,@sizeOf(RAWINPUTDEVICE)
        );
    }
};

pub const RAWINPUT = extern struct {
    header: RAWINPUTHEADER,
    data: extern union {
        mi: extern struct {
            usFlags: u16,
            _: u16,
            usButtonFlags: u16,
            usButtonData: i16,
            ulRawButtons: u32,
            lLastX: i32,
            lLastY: i32,
            ulExtraInformation: u32,
        },
        ki: extern struct {
            MakeCode: u16,
            Flags: u16,
            Reserved: u16,
            VKey: u16,
            Message: u32,
            ExtraInformation: u32,
        },
        hi: extern struct {
            dwSizeHid: u32,
            dwCount: u32,
            bRawData: [1]u8,
        },
    },

    pub fn HID(comptime n: usize) type {
        return extern struct {
            header: RAWINPUTHEADER,
            data: extern struct {
                dwSizeHid: u32,
                dwCount: u32,
                bRawData: [n]u8,
            },

            const Self = @This();
            pub fn getData(self: *Self, lParam: isize) i32 {
                var size: u32 = @sizeOf(Self);
                return GetRawInputData(lParam, 0x10000003, self, &size, @sizeOf(RAWINPUTHEADER));
            }
        };
    }

    extern "user32" fn GetRawInputData(isize, u32, ?*anyopaque, *u32, u32) callconv(WINAPI) i32;

    const RAWINPUTHEADER = extern struct {
        dwType: u32,
        dwSize: u32,
        hDevice: *anyopaque,
        wParam: usize
    };
};

const INPUT = extern struct {
    type: u32,
    input: extern union {
        mi: extern struct {
            dx: i32 = 0,
            dy: i32 = 0,
            mouseData: i32 = 0,
            dwFlags: u32 = 0,
            time: u32 = 0,
            dwExtraInfo: usize = 0,
        },
        ki: extern struct {
            wVK: u16 = 0,
            wScan: u16 = 0,
            dwFlags: u32 = 0,
            time: u32 = 0,
            dwExtraInfo: usize = 0,
        },
        hi: extern struct {
            uMsg: u32 = 0,
            wParamL: u16 = 0,
            wParamH: u16 = 0,
        }
    },
    pub fn send(input: INPUT) u32 {
        return SendInput(1, @ptrCast(&input), @sizeOf(INPUT));
    }
    extern "user32" fn SendInput(cInputs: u32, pInputs: [*]const INPUT, cbSize: i32) callconv(WINAPI) u32;
};

