#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "rosette_metal_support.h"
#include <algorithm>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>

namespace {
constexpr size_t max_bytes = 64 * 1024 * 1024;
constexpr size_t guard_bytes = 64;
constexpr uint8_t guard = 0xa7;
struct Context {
    id<MTLDevice> device;
    id<MTLCommandQueue> queue;
    id<MTLLibrary> library;
    id<MTLComputePipelineState> color, uniform, ctx1, dxt, dxt5a, dxt3a, dxn;
    std::mutex mutex;
    std::string name, error;
    bool terminal = false;
};
int invalid(Context* c, const char* reason) { if (c) c->error = reason; return -1; }
id<MTLBuffer> buffer(Context* c, size_t bytes, const void* source = nullptr) {
    if (bytes > max_bytes) return nil;
    auto b = [c->device newBufferWithLength:std::max(bytes, size_t(16)) + guard_bytes options:MTLResourceStorageModeShared];
    if (b) {
        memset(b.contents, guard, b.length);
        if (source && bytes) memcpy(b.contents, source, bytes);
    }
    return b;
}
bool guarded(id<MTLBuffer> b, size_t bytes) {
    auto p = static_cast<const uint8_t*>(b.contents);
    for (size_t i = bytes; i < b.length; ++i) if (p[i] != guard) return false;
    return true;
}
int finish(Context* c, id<MTLCommandBuffer> command) {
    if (!command) return invalid(c, "Command buffer allocation failed");
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [command addCompletedHandler:^(id<MTLCommandBuffer>) { dispatch_semaphore_signal(done); }];
    [command commit];
    // A timeout is terminal. It does not imply that pending GPU work was cancelled.
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC))) {
        c->terminal = true; c->error = "Native Metal completion timeout; context disabled"; return -2;
    }
    if (command.status != MTLCommandBufferStatusCompleted) {
        c->terminal = true;
        c->error = command.error.localizedDescription.UTF8String ?: "Native Metal command failed";
        return -2;
    }
    return 0;
}
int check_guards(Context* c, bool ok) {
    if (ok) return 0;
    c->terminal = true; c->error = "Native Metal buffer guard changed; context disabled"; return -3;
}
void dispatch(id<MTLComputeCommandEncoder> encoder, id<MTLComputePipelineState> pipeline, uint32_t count) {
    [encoder setComputePipelineState:pipeline];
    // Rounded dispatch deliberately exercises the shader's logical output bound.
    [encoder dispatchThreadgroups:MTLSizeMake((count + 63) / 64, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];
}
}

RosetteMetalContext rosette_metal_open(const char* path, char* message, size_t capacity) {
    @autoreleasepool {
        auto c = std::make_unique<Context>();
        c->device = MTLCreateSystemDefaultDevice();
        if (!c->device) c->device = MTLCopyAllDevices().firstObject;
        NSError* error = nil;
        if (c->device && path) c->library = [c->device newLibraryWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:path]] error:&error];
        if (c->library) {
            c->queue = [c->device newCommandQueue];
            c->color = [c->device newComputePipelineStateWithFunction:[c->library newFunctionWithName:@"rosette_color_7e3"] error:&error];
            c->uniform = [c->device newComputePipelineStateWithFunction:[c->library newFunctionWithName:@"rosette_uniform_gather"] error:&error];
            c->ctx1 = [c->device newComputePipelineStateWithFunction:[c->library newFunctionWithName:@"rosette_decode_ctx1"] error:&error];
            c->dxt = [c->device newComputePipelineStateWithFunction:[c->library newFunctionWithName:@"rosette_decode_dxt"] error:&error];
            c->dxt5a = [c->device newComputePipelineStateWithFunction:[c->library newFunctionWithName:@"rosette_decode_dxt5a"] error:&error];
            c->dxt3a = [c->device newComputePipelineStateWithFunction:[c->library newFunctionWithName:@"rosette_decode_dxt3a"] error:&error];
            c->dxn = [c->device newComputePipelineStateWithFunction:[c->library newFunctionWithName:@"rosette_decode_dxn"] error:&error];
        }
        if (!c->queue || !c->color || !c->uniform || !c->ctx1 || !c->dxt || !c->dxt5a || !c->dxt3a || !c->dxn) {
            if (message && capacity) snprintf(message, capacity, "device=%d library=%d queue=%d color=%d uniform=%d ctx1=%d dxt=%d dxt5a=%d dxt3a=%d dxn=%d: %s",
                c->device != nil,c->library != nil,c->queue != nil,c->color != nil,c->uniform != nil,c->ctx1 != nil,c->dxt != nil,
                c->dxt5a != nil,c->dxt3a != nil,c->dxn != nil,
                error.localizedDescription.UTF8String ?: "Metal device/library unavailable");
            return nullptr;
        }
        c->name = c->device.name.UTF8String;
        return c.release();
    }
}
void rosette_metal_close(RosetteMetalContext value) { delete static_cast<Context*>(value); }
const char* rosette_metal_device_name(RosetteMetalContext value) { return value ? static_cast<Context*>(value)->name.c_str() : ""; }
const char* rosette_metal_error(RosetteMetalContext value) { return value ? static_cast<Context*>(value)->error.c_str() : "Missing Metal context"; }

int rosette_metal_color7e3(RosetteMetalContext value, uint32_t count, uint32_t* output) {
    @autoreleasepool {
        auto c = static_cast<Context*>(value);
        if (!c || !output || !count || count > 1024) return invalid(c, "7e3 count must be 1..1024");
        std::lock_guard lock(c->mutex); if (c->terminal) return -2;
        const size_t bytes = size_t(count) * 16;
        auto result = buffer(c, bytes); auto command = [c->queue commandBuffer];
        if (!result || !command) return invalid(c, "Metal allocation failed");
        auto encoder = [command computeCommandEncoder];
        if (!encoder) return invalid(c, "Metal encoder allocation failed");
        [encoder setBuffer:result offset:0 atIndex:0]; [encoder setBytes:&count length:sizeof(count) atIndex:1];
        dispatch(encoder, c->color, count); [encoder endEncoding];
        if (int status = finish(c, command)) return status;
        if (int status = check_guards(c, guarded(result, bytes))) return status;
        memcpy(output, result.contents, bytes); return 0;
    }
}
int rosette_metal_uniform4(RosetteMetalContext value, const float* values, uint32_t rows, const int32_t* indices, uint32_t requests, float* output) {
    @autoreleasepool {
        auto c = static_cast<Context*>(value);
        const size_t input_bytes = size_t(rows) * 16, output_bytes = size_t(requests) * 16;
        if (!c || (rows && !values) || !indices || !output || !requests || input_bytes > max_bytes || output_bytes > max_bytes)
            return invalid(c, "Uniform pointer/count exceeds bounded API contract");
        std::lock_guard lock(c->mutex); if (c->terminal) return -2;
        auto input = buffer(c, input_bytes, values), ids = buffer(c, size_t(requests)*4, indices), result = buffer(c, output_bytes);
        auto command = [c->queue commandBuffer];
        if (!input || !ids || !result || !command) return invalid(c, "Metal allocation failed");
        auto encoder = [command computeCommandEncoder];
        if (!encoder) return invalid(c, "Metal encoder allocation failed");
        const uint32_t bounds[] = {rows, requests};
        [encoder setBuffer:input offset:0 atIndex:0]; [encoder setBuffer:ids offset:0 atIndex:1]; [encoder setBuffer:result offset:0 atIndex:2];
        [encoder setBytes:bounds length:sizeof(bounds) atIndex:3]; dispatch(encoder, c->uniform, requests); [encoder endEncoding];
        if (int status = finish(c, command)) return status;
        if (int status = check_guards(c, guarded(input, input_bytes) && guarded(ids, size_t(requests)*4) && guarded(result, output_bytes))) return status;
        memcpy(output, result.contents, output_bytes); return 0;
    }
}
int rosette_metal_ctx1(RosetteMetalContext value, const uint32_t* blocks, uint32_t block_count, uint32_t width, uint32_t height, uint32_t pitch, uint32_t endian, uint8_t* output) {
    @autoreleasepool {
        auto c = static_cast<Context*>(value);
        const uint64_t columns = (uint64_t(width)+3)/4, rows = (uint64_t(height)+3)/4;
        const uint64_t needed = rows ? (rows-1)*pitch + columns : 0;
        if (!c || !blocks || !output || !width || !height || width > 4096 || height > 4096 || endian > 3 || pitch < columns || needed > block_count || uint64_t(block_count)*8 > max_bytes)
            return invalid(c, "CTX1 dimensions/pitch/endian/block range invalid");
        std::lock_guard lock(c->mutex); if (c->terminal) return -2;
        auto source = buffer(c, size_t(block_count)*8, blocks);
        auto desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRG8Unorm width:width height:height mipmapped:NO];
        desc.storageMode = MTLStorageModeShared; desc.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
        auto texture = [c->device newTextureWithDescriptor:desc]; auto command = [c->queue commandBuffer];
        if (!source || !texture || !command) return invalid(c, "Metal allocation failed");
        auto encoder = [command computeCommandEncoder];
        if (!encoder) return invalid(c, "Metal encoder allocation failed");
        const uint32_t bounds[] = {width, height, pitch, block_count, endian};
        [encoder setComputePipelineState:c->ctx1]; [encoder setBuffer:source offset:0 atIndex:0];
        [encoder setBytes:bounds length:sizeof(bounds) atIndex:1]; [encoder setTexture:texture atIndex:0];
        [encoder dispatchThreadgroups:MTLSizeMake((width+7)/8,(height+7)/8,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)]; [encoder endEncoding];
        if (int status = finish(c, command)) return status;
        if (int status = check_guards(c, guarded(source, size_t(block_count)*8))) return status;
        [texture getBytes:output bytesPerRow:size_t(width)*2 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0]; return 0;
    }
}
int rosette_metal_dxt(RosetteMetalContext value, const uint32_t* words, uint32_t count, uint32_t width, uint32_t height, uint32_t pitch, uint32_t endian, uint32_t format, uint8_t* output) {
    @autoreleasepool {
        auto c = static_cast<Context*>(value);
        const uint64_t columns = (uint64_t(width)+3)/4, rows = (uint64_t(height)+3)/4;
        const uint64_t stride = format == 1 ? 2 : 4;
        const uint64_t needed = rows ? ((rows-1)*pitch+columns)*stride : 0;
        if (!c || !words || !output || !width || !height || width > 4096 || height > 4096 || endian > 3 ||
            (format != 1 && format != 3 && format != 5) || pitch < columns || needed > count || uint64_t(count)*4 > max_bytes)
            return invalid(c, "DXT dimensions/pitch/endian/format/source word range invalid");
        std::lock_guard lock(c->mutex); if (c->terminal) return -2;
        auto source = buffer(c, size_t(count)*4, words);
        auto desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];
        desc.storageMode = MTLStorageModeShared; desc.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
        auto texture = [c->device newTextureWithDescriptor:desc]; auto command = [c->queue commandBuffer];
        if (!source || !texture || !command) return invalid(c, "Metal allocation failed");
        auto encoder = [command computeCommandEncoder];
        if (!encoder) return invalid(c, "Metal encoder allocation failed");
        const uint32_t bounds[] = {width,height,pitch,count,endian,format};
        [encoder setComputePipelineState:c->dxt]; [encoder setBuffer:source offset:0 atIndex:0];
        [encoder setBytes:bounds length:sizeof(bounds) atIndex:1]; [encoder setTexture:texture atIndex:0];
        [encoder dispatchThreadgroups:MTLSizeMake((width+7)/8,(height+7)/8,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)]; [encoder endEncoding];
        if (int status = finish(c, command)) return status;
        if (int status = check_guards(c, guarded(source, size_t(count)*4))) return status;
        [texture getBytes:output bytesPerRow:size_t(width)*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0]; return 0;
    }
}
int rosette_metal_bc45(RosetteMetalContext value, const uint32_t* words, uint32_t count, uint32_t width, uint32_t height, uint32_t pitch, uint32_t endian, uint32_t format, uint8_t* output) {
    @autoreleasepool {
        auto c = static_cast<Context*>(value);
        const uint64_t columns = (uint64_t(width)+3)/4, rows = (uint64_t(height)+3)/4;
        const uint64_t stride = format == 2 ? 4 : 2;
        const uint64_t needed = rows ? ((rows-1)*pitch+columns)*stride : 0;
        if (!c || !words || !output || !width || !height || width > 4096 || height > 4096 || endian > 3 ||
            (format != 1 && format != 2 && format != 3) || pitch < columns || needed > count || uint64_t(count)*4 > max_bytes)
            return invalid(c, "DXT5A/DXN/DXT3A dimensions/pitch/endian/format/source word range invalid");
        std::lock_guard lock(c->mutex); if (c->terminal) return -2;
        const size_t texel_bytes = format == 2 ? 2 : 1;
        auto source = buffer(c, size_t(count)*4, words);
        auto desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:(format == 2 ? MTLPixelFormatRG8Unorm : MTLPixelFormatR8Unorm) width:width height:height mipmapped:NO];
        desc.storageMode = MTLStorageModeShared; desc.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
        auto texture = [c->device newTextureWithDescriptor:desc]; auto command = [c->queue commandBuffer];
        if (!source || !texture || !command) return invalid(c, "Metal allocation failed");
        auto encoder = [command computeCommandEncoder];
        if (!encoder) return invalid(c, "Metal encoder allocation failed");
        const uint32_t bounds[] = {width,height,pitch,count,endian,format};
        [encoder setComputePipelineState:(format == 1 ? c->dxt5a : format == 2 ? c->dxn : c->dxt3a)]; [encoder setBuffer:source offset:0 atIndex:0];
        [encoder setBytes:bounds length:sizeof(bounds) atIndex:1]; [encoder setTexture:texture atIndex:0];
        [encoder dispatchThreadgroups:MTLSizeMake((width+7)/8,(height+7)/8,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)]; [encoder endEncoding];
        if (int status = finish(c, command)) return status;
        if (int status = check_guards(c, guarded(source, size_t(count)*4))) return status;
        [texture getBytes:output bytesPerRow:size_t(width)*texel_bytes fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0]; return 0;
    }
}
int rosette_metal_order_probe(RosetteMetalContext value, uint32_t samples, uint32_t draws, uint32_t* output) {
    @autoreleasepool {
        auto c = static_cast<Context*>(value);
        if (!c || !output || (samples != 1 && samples != 4) || !draws || draws > 16) return invalid(c, "Ordering probe permits 1x/4x and 1..16 draws");
        std::lock_guard lock(c->mutex); if (c->terminal) return -2;
        if (!c->device.rasterOrderGroupsSupported || ![c->device supportsTextureSampleCount:samples]) return invalid(c, "Native ordering/sample mode unavailable");
        auto desc = [MTLRenderPipelineDescriptor new];
        desc.vertexFunction = [c->library newFunctionWithName:@"rosette_fsi_triangle"];
        desc.fragmentFunction = [c->library newFunctionWithName:@"rosette_fsi_order"];
        desc.rasterSampleCount = samples; desc.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
        NSError* error = nil; auto pipeline = [c->device newRenderPipelineStateWithDescriptor:desc error:&error];
        if (!pipeline) return invalid(c, error.localizedDescription.UTF8String ?: "Ordering pipeline unavailable");
        auto texdesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:2 height:2 mipmapped:NO];
        texdesc.textureType = samples == 1 ? MTLTextureType2D : MTLTextureType2DMultisample;
        texdesc.sampleCount = samples; texdesc.storageMode = MTLStorageModePrivate; texdesc.usage = MTLTextureUsageRenderTarget;
        auto target = [c->device newTextureWithDescriptor:texdesc]; auto data = buffer(c, size_t(4*samples)*4);
        auto command = [c->queue commandBuffer];
        if (!target || !data || !command) return invalid(c, "Metal allocation failed");
        memset(data.contents, 0, size_t(4*samples)*4);
        auto pass = [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = target; pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].storeAction = MTLStoreActionDontCare;
        auto encoder = [command renderCommandEncoderWithDescriptor:pass];
        if (!encoder) return invalid(c, "Metal render encoder allocation failed");
        [encoder setRenderPipelineState:pipeline]; [encoder setFragmentBuffer:data offset:0 atIndex:0];
        for (uint32_t i=1; i<=draws; ++i) {
            const uint32_t bounds[] = {2,2,samples,4*samples,i};
            [encoder setFragmentBytes:bounds length:sizeof(bounds) atIndex:1];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        }
        [encoder endEncoding]; if (int status = finish(c, command)) return status;
        if (int status = check_guards(c, guarded(data, size_t(4*samples)*4))) return status;
        memcpy(output, data.contents, size_t(4*samples)*4); return 0;
    }
}
