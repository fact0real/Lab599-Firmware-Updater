#import "Lab599SerialPort.h"
#import <errno.h>
#import <fcntl.h>
#import <math.h>
#import <poll.h>
#import <sys/ioctl.h>
#import <time.h>
#import <unistd.h>

NSString *const Lab599SerialErrorDomain = @"Lab599SerialError";
@implementation Lab599Cancellation
@end

double Lab599MonotonicTime(void) {
    struct timespec stamp;
    clock_gettime(CLOCK_MONOTONIC, &stamp);
    return stamp.tv_sec + stamp.tv_nsec / 1e9;
}
BOOL Lab599Pause(double seconds, Lab599Cancellation *token) {
    double deadline = Lab599MonotonicTime() + seconds;
    while (!token.cancelled) {
        double remaining = deadline - Lab599MonotonicTime();
        if (remaining <= 0) return YES;
        struct timespec delay = {0, (long)(MIN(remaining, 0.01) * 1e9)};
        nanosleep(&delay, NULL);
    }
    return NO;
}
static BOOL Error(NSError **error, Lab599SerialError code, NSString *message) {
    if (error) *error = [NSError errorWithDomain:Lab599SerialErrorDomain code:code
        userInfo:@{NSLocalizedDescriptionKey: message}];
    return NO;
}
static BOOL SystemError(NSError **error, NSString *action) {
    int saved = errno;
    return Error(error, Lab599SerialIOError, [NSString stringWithFormat:@"%@: %s", action, strerror(saved)]);
}
static BOOL Cancelled(Lab599Cancellation *token, NSError **error) {
    if (!token.cancelled) return NO;
    Error(error, Lab599SerialCancelled, @"Stopped by the user.");
    return YES;
}

@implementation Lab599SerialPort {
    int _fd;
}
- (instancetype)init {
    if ((self = [super init])) _fd = -1;
    return self;
}
+ (instancetype)openPath:(NSString *)path speed:(speed_t)speed error:(NSError **)error {
    if (!path.length) { Error(error, Lab599SerialIOError, @"Select a serial port."); return nil; }
    Lab599SerialPort *port = [self new];
    port->_fd = open(path.fileSystemRepresentation, O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC);
    if (port->_fd < 0) { SystemError(error, @"Opening port (close other radio applications)"); return nil; }
    if (ioctl(port->_fd, TIOCEXCL) < 0) { SystemError(error, @"Obtaining exclusive serial access"); return nil; }
    struct termios settings;
    if (tcgetattr(port->_fd, &settings) < 0) { SystemError(error, @"Reading serial settings"); return nil; }
    cfmakeraw(&settings);
    settings.c_iflag = settings.c_oflag = settings.c_lflag = 0;
    settings.c_cflag &= ~(CSIZE | PARENB | PARODD | CSTOPB | HUPCL |
        CRTSCTS | CDTR_IFLOW | CDSR_OFLOW | CCAR_OFLOW);
    settings.c_cflag |= CLOCAL | CREAD | CS8;
    settings.c_cc[VMIN] = settings.c_cc[VTIME] = 0;
    if (cfsetispeed(&settings, speed) < 0 || cfsetospeed(&settings, speed) < 0 ||
        tcsetattr(port->_fd, TCSANOW, &settings) < 0 || tcflush(port->_fd, TCIOFLUSH) < 0 ||
        tcgetattr(port->_fd, &settings) < 0) {
        SystemError(error, @"Configuring serial port"); return nil;
    }
    if (cfgetispeed(&settings) != speed || cfgetospeed(&settings) != speed ||
        (settings.c_cflag & CSIZE) != CS8 ||
        (settings.c_cflag & (PARENB | CSTOPB | CRTSCTS | CDTR_IFLOW | CDSR_OFLOW | CCAR_OFLOW)) ||
        (settings.c_iflag & (IXON | IXOFF | IXANY))) {
        Error(error, Lab599SerialIOError, @"The driver did not accept the requested baud rate, 8N1 and no flow control."); return nil;
    }
    return port;
}
- (BOOL)discardInput:(NSError **)error {
    return tcflush(_fd, TCIFLUSH) == 0 ? YES : SystemError(error, @"Clearing stale serial input");
}
- (BOOL)assertDTRAndRTS:(NSError **)error {
    int bits = TIOCM_DTR | TIOCM_RTS;
    return ioctl(_fd, TIOCMBIS, &bits) == 0 ? YES : SystemError(error, @"Setting Memory utility DTR/RTS signals");
}
- (BOOL)writeData:(NSData *)data timeout:(double)timeout cancellation:(Lab599Cancellation *)token error:(NSError **)error {
    if (!isfinite(timeout) || timeout <= 0) return Error(error, Lab599SerialIOError, @"Invalid write timeout.");
    double deadline = Lab599MonotonicTime() + timeout;
    NSUInteger offset = 0;
    while (offset < data.length) {
        if (Cancelled(token, error)) return NO;
        if (Lab599MonotonicTime() >= deadline) return Error(error, Lab599SerialTimeout, @"Timed out writing the CAT command.");
        ssize_t count = write(_fd, (const uint8_t *)data.bytes + offset, data.length - offset);
        if (count > 0) offset += (NSUInteger)count;
        else if (count < 0 && errno == EINTR) continue;
        else if (count == 0 || errno == EAGAIN || errno == EWOULDBLOCK) Lab599Pause(0.001, token);
        else return SystemError(error, @"Writing CAT command");
    }
    for (;;) {
        if (Cancelled(token, error)) return NO;
        if (Lab599MonotonicTime() >= deadline) return Error(error, Lab599SerialTimeout, @"The serial output queue did not drain.");
        int pending = 0;
        if (ioctl(_fd, TIOCOUTQ, &pending) < 0) {
            if (errno == EINTR) continue;
            return SystemError(error, @"Checking serial output queue");
        }
        if (!pending) return YES;
        Lab599Pause(0.001, token);
    }
}
- (NSData *)readMaximum:(NSUInteger)maximum timeout:(double)timeout cancellation:(Lab599Cancellation *)token error:(NSError **)error {
    if (!maximum || !isfinite(timeout) || timeout <= 0) {
        Error(error, Lab599SerialIOError, @"Invalid serial read options."); return nil;
    }
    double deadline = Lab599MonotonicTime() + timeout;
    while (Lab599MonotonicTime() < deadline) {
        if (Cancelled(token, error)) return nil;
        struct pollfd item = {.fd = _fd, .events = POLLIN};
        int wait = (int)MAX(1, MIN(20, ceil((deadline - Lab599MonotonicTime()) * 1000)));
        int ready = poll(&item, 1, wait);
        if (ready < 0) {
            if (errno == EINTR) continue;
            SystemError(error, @"Waiting for CAT data"); return nil;
        }
        if (item.revents & (POLLHUP | POLLERR | POLLNVAL)) {
            Error(error, Lab599SerialIOError, @"The serial connection was lost."); return nil;
        }
        if (!(item.revents & POLLIN)) continue;
        uint8_t bytes[1024];
        ssize_t count = read(_fd, bytes, MIN(maximum, sizeof(bytes)));
        if (count > 0) return [NSData dataWithBytes:bytes length:(NSUInteger)count];
        if (count < 0 && errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK) {
            SystemError(error, @"Reading CAT data"); return nil;
        }
    }
    if (!Cancelled(token, error)) Error(error, Lab599SerialTimeout, @"No serial data within the read deadline.");
    return nil;
}
- (void)close {
    if (_fd >= 0) { close(_fd); _fd = -1; }
}
- (void)dealloc { [self close]; }
@end
