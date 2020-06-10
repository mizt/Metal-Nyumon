#import <Cocoa/Cocoa.h>
#import "MetalView.h"

#define FPS 60

class App {
    
    private:
    
        int width = 1280;
        int height = 720;
    
        NSWindow *win;
        MetalView *view;
        dispatch_source_t timer;
        CGRect rect = CGRectMake(0,0,width,height);
    
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
        dispatch_fd_t fd;
        bool lock = false;
        double timestamp=-1;
        NSString *path = [[[NSBundle mainBundle] URLForResource:@"o0" withExtension:@"metallib"] path];
    
        bool isCapture = false;
        unsigned int *buffer = nullptr;
        NSBitmapImageRep *rep;
    
        NSFileManager *fileManager = [NSFileManager defaultManager];
    
    public :
    
        void capture() {
            this->isCapture = true;
        }
    
        App() {
            
             this->rep = [[NSBitmapImageRep alloc]
                initWithBitmapDataPlanes:NULL
                pixelsWide:this->width
                pixelsHigh:this->height
                bitsPerSample:8
                samplesPerPixel:4
                hasAlpha:YES
                isPlanar:NO
                colorSpaceName:NSDeviceRGBColorSpace
                bitmapFormat:NSBitmapFormatAlphaFirst
                bytesPerRow:this->width<<2
                bitsPerPixel:0
            ];
            
            this->view = [[MetalView alloc] initWithFrame:rect];
            if(this->view) {
                
                this->win = [[NSWindow alloc] initWithContentRect:rect styleMask:1 backing:NSBackingStoreBuffered defer:NO];
                [this->win setBackgroundColor:[NSColor blackColor]];
                [this->win center];
                
                this->timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_queue_create("org.mizt",0));
                dispatch_source_set_timer(this->timer,dispatch_time(0,0),(1.0/FPS)*1000000000,0);
                dispatch_source_set_event_handler(this->timer,^{
                    dispatch_async(dispatch_get_main_queue(),^{
                                                
                        if(this->lock==false) {
                            if([fileManager fileExistsAtPath:this->path]) {
                                double date = [[[fileManager attributesOfItemAtPath:this->path error:nil] objectForKey:NSFileModificationDate] timeIntervalSince1970];
                                
                                if(this->timestamp!=-1&&this->timestamp!=date) {
                                    
                                    this->timestamp = date;
                                    
                                    NSError *error = nil;
                                    NSDictionary *attributes = [fileManager attributesOfItemAtPath:this->path error:&error];
                                    if(!error) {
                                        long size = [[attributes objectForKey:NSFileSize] integerValue];
                                        if(size>0) {
                                            
                                            this->lock = true;
                                            
                                            this->fd = open([this->path UTF8String],O_RDONLY);
                                            dispatch_read(fd,size,dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^(dispatch_data_t d, int e) {
                                                [this->view reloadShader:d];
                                                close(this->fd);
                                                this->lock = false;
                                            });
                                            
                                        }
                                    }
                                }
                                
                                if(this->timestamp==-1) this->timestamp = date;
                            }
                        }
                    });
                    
                    if(this->view) {
                        
                        @autoreleasepool {
                            
                            [this->view update:
                             ^(id<MTLCommandBuffer> commandBuffer){
                                 
                                 if(this->buffer&&this->isCapture) {
                                     
                                    id<MTLTexture> texture = [this->view drawableTexture];
                                    [texture getBytes:this->buffer bytesPerRow:(this->width<<2) fromRegion:MTLRegionMake2D(0,0,this->width,this->height) mipmapLevel:0];
                                     
                                     unsigned int *bmp = (unsigned int *)[rep bitmapData];
                                     unsigned int *buf = this->buffer;
                                     
                                     for(int k=0; k<this->width*this->height; k++) {
                                         
                                         unsigned int pixels = *buf++;
                                         unsigned char a = pixels>>24;
                                         unsigned char r = (pixels>>16)&0xFF;
                                         unsigned char g = (pixels>>8)&0xFF;
                                         unsigned char b = pixels&0xFF;
                                         
                                         *bmp++ = b<<24|g<<16|r<<8|a;
                                     }
                                     
                                     [[NSPasteboard generalPasteboard] clearContents];
                                     [[NSPasteboard generalPasteboard] setData:[this->rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] forType:NSPasteboardTypePNG];

                                     this->isCapture = false;
                                    
                                 }
                                 
                                 dispatch_semaphore_signal(semaphore);
                                 
                             }];
                            
                            dispatch_semaphore_wait(semaphore,DISPATCH_TIME_FOREVER);
                            [this->view cleanup];

                        }
                    }
                    
                    static dispatch_once_t predicate;
                    dispatch_once(&predicate,^{
                        dispatch_async(dispatch_get_main_queue(),^{
                            if(this->win) {
                                if(this->view) {
                                    
                                    [[this->win contentView] addSubview:this->view];
                                    this->buffer = new unsigned int[this->width*this->height];
                                    for(int i=0; i<this->height; i++) {
                                        for(int j=0; j<this->width; j++) {
                                            this->buffer[i*this->width+j] = 0x00000000;
                                        }
                                    }
                                    
                                    id<MTLTexture> texture = [this->view texture];
                                    [texture replaceRegion:MTLRegionMake2D(0,0,this->width,this->height) mipmapLevel:0 withBytes:this->buffer bytesPerRow:this->width<<2];
                                    
                                }
                                [this->win makeKeyAndOrderFront:nil];
                            }
                        });
                    });
                    
                    
                });
                dispatch_resume(timer);
            }
        }
    
        ~App() {
            
            if(this->timer) {
                dispatch_source_cancel(this->timer);
            }
            
            if(this->buffer) {
                delete[] this->buffer;
                this->buffer = nullptr;
            }
            
            this->view = nil;
            if(this->win) [this->win close];
        }
};

@interface AppDelegate:NSObject <NSApplicationDelegate> {
    App *m;
}
@end

@implementation AppDelegate

-(void)Capture:(id)sender {
    if(m) m->capture();
}

-(void)applicationDidFinishLaunching:(NSNotification*)aNotification {
    
    id menu = [[NSMenu alloc] init];
    id rootMenuItem = [[NSMenuItem alloc] init];
    [menu addItem:rootMenuItem];
    id appMenu = [[NSMenu alloc] init];
    [appMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Capture" action:@selector(Capture:) keyEquivalent:@"c"]];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"]];
    [rootMenuItem setSubmenu:appMenu];
    [NSApp setMainMenu:menu];
    
    m = new App();
    
}
-(void)applicationWillTerminate:(NSNotification *)aNotification {
    if(m) delete m;
}
@end

int main (int argc, const char * argv[]) {
    
    srand(CFAbsoluteTimeGetCurrent());
    srandom(CFAbsoluteTimeGetCurrent());
    
    id app = [NSApplication sharedApplication];
    id delegat = [AppDelegate alloc];
    [app setDelegate:delegat];
    [app run];
    
    return 0;
}
