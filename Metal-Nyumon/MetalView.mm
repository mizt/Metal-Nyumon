#import "MetalView.h"

namespace Plane {
    
    static const float vertexData[6][4] = {
        { -1.f,-1.f, 0.f, 1.f },
        {  1.f,-1.f, 0.f, 1.f },
        { -1.f, 1.f, 0.f, 1.f },
        {  1.f,-1.f, 0.f, 1.f },
        { -1.f, 1.f, 0.f, 1.f },
        {  1.f, 1.f, 0.f, 1.f }
    };
    
    static const float textureCoordinateData[6][2] = {
        { 0.f, 0.f },
        { 1.f, 0.f },
        { 0.f, 1.f },
        { 1.f, 0.f },
        { 0.f, 1.f },
        { 1.f, 1.f }
    };
}

@interface MetalView() {
    
    __weak CAMetalLayer *_metalLayer;
    MTLRenderPassDescriptor *_renderPassDescriptor;
    
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLLibrary> _library;
    id<MTLRenderPipelineState> _renderPipelineState;
    id<CAMetalDrawable> _metalDrawable;
    
    id<MTLTexture> _drawabletexture;    
    id<MTLTexture> _texture;

    id<MTLBuffer> _timeBuffer;
    id<MTLBuffer> _resolutionBuffer;
    id<MTLBuffer> _mouseBuffer;
    
    id<MTLBuffer> _vertexBuffer;
    id<MTLBuffer> _texcoordBuffer;
    
    id<MTLArgumentEncoder> _argumentEncoder;
    id<MTLBuffer> _argumentEncoderBuffer;
    
    MTLRenderPipelineDescriptor *_renderPipelineDescriptor;
    
    CGRect _frame;
    double _starttime;
    
}
@end

@implementation MetalView

+(Class)layerClass { return [CAMetalLayer class]; }
-(BOOL)wantsUpdateLayer { return YES; }
-(void)updateLayer { [super updateLayer]; }
-(id<MTLTexture>)texture { return _texture; }
-(id<MTLTexture>)drawableTexture { return _drawabletexture; }
-(void)cleanup { _metalDrawable = nil; }
-(bool)setupShader {
    
    id<MTLFunction> vertexFunction  = [_library newFunctionWithName:@"vertexShader"];
    if(!vertexFunction) return nil;
    
    id<MTLFunction> fragmentFunction = [_library newFunctionWithName:@"fragmentShader"];
    if(!fragmentFunction) return nil;
    
    if(_renderPipelineDescriptor==nil) {
        _renderPipelineDescriptor = [MTLRenderPipelineDescriptor new];
        if(!_renderPipelineDescriptor) return nil;
        
        _argumentEncoder = [fragmentFunction newArgumentEncoderWithBufferIndex:0];
     }
    
    _renderPipelineDescriptor.depthAttachmentPixelFormat      = MTLPixelFormatInvalid;
    _renderPipelineDescriptor.stencilAttachmentPixelFormat    = MTLPixelFormatInvalid;
    _renderPipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    
    MTLRenderPipelineColorAttachmentDescriptor *colorAttachment = _renderPipelineDescriptor.colorAttachments[0];
    colorAttachment.blendingEnabled = YES;
    colorAttachment.rgbBlendOperation = MTLBlendOperationAdd;
    colorAttachment.alphaBlendOperation = MTLBlendOperationAdd;
    colorAttachment.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    colorAttachment.sourceAlphaBlendFactor = MTLBlendFactorOne;
    colorAttachment.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    colorAttachment.destinationAlphaBlendFactor = MTLBlendFactorOne;
    
    _renderPipelineDescriptor.sampleCount = 1;
   
    _renderPipelineDescriptor.vertexFunction = vertexFunction;
    _renderPipelineDescriptor.fragmentFunction = fragmentFunction;
    
    NSError *error = nil;
    _renderPipelineState = [_device newRenderPipelineStateWithDescriptor:_renderPipelineDescriptor error:&error];
    if(error||!_renderPipelineState) return true;
    
    return false;
}

-(bool)reloadShader:(dispatch_data_t)data {
    
    NSError *error = nil;
    _library = [_device newLibraryWithData:data error:&error];
    if(error||!_library) return true;

    if([self setupShader]) return true;
    
    return false;
}

-(id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if(self) {
        
        _frame = frame;
        _starttime = CFAbsoluteTimeGetCurrent();

        self.wantsLayer = YES;
        self.layer = [CAMetalLayer layer];
        _metalLayer = (CAMetalLayer *)self.layer;
        _device = MTLCreateSystemDefaultDevice();
        
        _metalLayer.device = _device;
        _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        _metalLayer.colorspace = CGColorSpaceCreateDeviceRGB();
        
        _metalLayer.opaque = NO;
        _metalLayer.framebufferOnly = NO;
        _metalLayer.displaySyncEnabled = YES;
        
        _commandQueue = [_device newCommandQueue];
        if(!_commandQueue) return nil;
        
       
        NSString *path = [[NSBundle mainBundle] pathForResource:@"main" ofType:@"metallib"];
        if(!path) return nil;
        
        NSError *error = nil;
        _library = [_device newLibraryWithFile:path error:&error];
        if(error||!_library) return nil;
        
        if([self setupShader]) return nil;
      
        MTLTextureDescriptor *texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:frame.size.width height:frame.size.height mipmapped:NO];
        if(!texDesc) return nil;
        
        _texture = [_device newTextureWithDescriptor:texDesc];
        if(!_texture)  return nil;
        
        _timeBuffer = [_device newBufferWithLength:sizeof(float) options:MTLResourceOptionCPUCacheModeDefault];
        if(!_timeBuffer) return nil;
        
        _resolutionBuffer = [_device newBufferWithLength:sizeof(float)*2 options:MTLResourceOptionCPUCacheModeDefault];
        if(!_resolutionBuffer) return nil;
        
        float *resolutionBuffer = (float *)[_resolutionBuffer contents];
        resolutionBuffer[0] = _frame.size.width;
        resolutionBuffer[1] = _frame.size.height;
        
        _mouseBuffer = [_device newBufferWithLength:sizeof(float)*2 options:MTLResourceOptionCPUCacheModeDefault];
        if(!_mouseBuffer) return nil;
        
        _vertexBuffer = [_device newBufferWithBytes:Plane::vertexData length:6*sizeof(float)*4 options:MTLResourceOptionCPUCacheModeDefault];
        if(!_vertexBuffer) return nil;
        
        _texcoordBuffer = [_device newBufferWithBytes:Plane::textureCoordinateData length:6*sizeof(float)*2 options:MTLResourceOptionCPUCacheModeDefault];
        if(!_texcoordBuffer) return nil;
        
        _argumentEncoderBuffer = [_device newBufferWithLength:sizeof(float)*[_argumentEncoder encodedLength] options:MTLResourceOptionCPUCacheModeDefault];
        [_argumentEncoder setArgumentBuffer:_argumentEncoderBuffer offset:0];

        [_argumentEncoder setBuffer:_timeBuffer offset:0 atIndex:0];
        [_argumentEncoder setBuffer:_resolutionBuffer offset:0 atIndex:1];
        [_argumentEncoder setBuffer:_mouseBuffer offset:0 atIndex:2];
        [_argumentEncoder setTexture:_texture atIndex:3];
        
    }
    return self;
}

-(id<MTLCommandBuffer>)setupCommandBuffer {
	
    if(!_metalDrawable) {
        _metalDrawable = [_metalLayer nextDrawable];
    }
    
    if(!_metalDrawable) {
        _renderPassDescriptor = nil;
    }
    else {
        
        if(_renderPassDescriptor == nil) {
            _renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
        }
    }
    
    if(_metalDrawable&&_renderPassDescriptor) {
        
        id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
        
        float *timeBuffer = (float *)[_timeBuffer contents];
        timeBuffer[0] = CFAbsoluteTimeGetCurrent()-_starttime;
        
        float *mouseBuffer = (float *)[_mouseBuffer contents];
        
        double x = _frame.origin.x;
        double y = _frame.origin.y;
        double w = _frame.size.width;
        double h = _frame.size.height;
        
        NSPoint mouseLoc = [NSEvent mouseLocation]; //get current mouse position
        mouseBuffer[0] = (mouseLoc.x-x)/w;
        mouseBuffer[1] = (mouseLoc.y-y)/h;
        
        MTLRenderPassColorAttachmentDescriptor *colorAttachment = _renderPassDescriptor.colorAttachments[0];
        colorAttachment.texture = _metalDrawable.texture;
        colorAttachment.loadAction  = MTLLoadActionClear;
        colorAttachment.clearColor  = MTLClearColorMake(0.0f,0.0f,0.0f,0.0f);
        colorAttachment.storeAction = MTLStoreActionStore;
        
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_renderPassDescriptor];
        
        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderEncoder setRenderPipelineState:_renderPipelineState];
        
        
        [renderEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
        [renderEncoder setVertexBuffer:_texcoordBuffer offset:0 atIndex:1];

        [renderEncoder useResource:_timeBuffer usage:MTLResourceUsageRead];
        [renderEncoder useResource:_resolutionBuffer usage:MTLResourceUsageRead];
        [renderEncoder useResource:_mouseBuffer usage:MTLResourceUsageRead];
        [renderEncoder useResource:_texture usage:MTLResourceUsageSample];

        [renderEncoder setFragmentBuffer:_argumentEncoderBuffer offset:0 atIndex:0];

        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:1];
        [renderEncoder endEncoding];
        [commandBuffer presentDrawable:_metalDrawable];
        
        _drawabletexture = _metalDrawable.texture;

        return commandBuffer;
    }
    
    return nil;
}

-(void)update:(void (^)(id<MTLCommandBuffer>))onComplete {
    
    if(_renderPipelineState) {
        
        id<MTLCommandBuffer> commandBuffer = [self setupCommandBuffer];
        if(commandBuffer) {
            [commandBuffer addCompletedHandler:onComplete];
            [commandBuffer commit];
            [commandBuffer waitUntilCompleted];
        }
    }
}

-(void)dealloc {
    
}

@end
