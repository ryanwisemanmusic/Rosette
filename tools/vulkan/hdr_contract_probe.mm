// Bounded synthetic HDR contract runner. No game data or guest execution.
#define VK_NO_PROTOTYPES
#include "../../pkg/vendor/sources/vulkan-headers/1.4.313/include/vulkan/vulkan.h"
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#define FUNCTIONS(X) \
 X(CreateInstance) X(DestroyInstance) X(EnumeratePhysicalDevices) X(GetPhysicalDeviceProperties) \
 X(GetPhysicalDeviceMemoryProperties) X(GetPhysicalDeviceQueueFamilyProperties) X(EnumerateDeviceExtensionProperties) \
 X(CreateDevice) X(DestroyDevice) X(GetDeviceQueue) X(CreateBuffer) X(DestroyBuffer) \
 X(GetBufferMemoryRequirements) X(AllocateMemory) X(FreeMemory) X(BindBufferMemory) X(MapMemory) X(UnmapMemory) \
 X(CreateDescriptorSetLayout) X(DestroyDescriptorSetLayout) X(CreatePipelineLayout) X(DestroyPipelineLayout) \
 X(CreateDescriptorPool) X(DestroyDescriptorPool) X(AllocateDescriptorSets) X(UpdateDescriptorSets) \
 X(CreateShaderModule) X(DestroyShaderModule) X(CreateComputePipelines) X(DestroyPipeline) \
 X(CreateCommandPool) X(DestroyCommandPool) X(AllocateCommandBuffers) X(BeginCommandBuffer) X(EndCommandBuffer) \
 X(CmdBindPipeline) X(CmdBindDescriptorSets) X(CmdDispatch) X(CmdPipelineBarrier) \
 X(QueueSubmit) X(CreateFence) X(DestroyFence) X(WaitForFences)
#define DECLARE(n) static PFN_vk##n vk##n;
FUNCTIONS(DECLARE)
#define CHECK(e) do {VkResult r=(e);if(r!=VK_SUCCESS){fprintf(stderr,"%s failed %d\n",#e,r);exit(2);}}while(0)
static const size_t GUARD=256;
static void require(bool ok,const char* message){if(!ok){fprintf(stderr,"%s\n",message);exit(2);}}
static std::vector<unsigned char> read(const char* path) {
 FILE* f=fopen(path,"rb");require(f,"cannot open input");fseek(f,0,SEEK_END);long n=ftell(f);rewind(f);
 require(n>0 && n<=8*1024*1024,"input extent refused");std::vector<unsigned char> data(n);
 require(fread(data.data(),1,n,f)==size_t(n),"short read");fclose(f);return data;
}
static void save(const char* prefix,const char* suffix,const void* data,size_t bytes){
 std::string p=std::string(prefix)+suffix;FILE* f=fopen(p.c_str(),"wb");require(f,"cannot open output");
 require(fwrite(data,1,bytes,f)==bytes,"short write");fclose(f);
}
static void guards(const unsigned char* data,size_t payload){
 for(size_t i=0;i<GUARD;i++)require(data[i]==0xA5 && data[GUARD+payload+i]==0xA5,"guard corruption");
}
struct Buffer{VkBuffer buffer;VkDeviceMemory memory;unsigned char* bytes;};
static Buffer make_buffer(VkDevice device,VkPhysicalDeviceMemoryProperties mem,size_t payload){
 Buffer b{};VkBufferCreateInfo bi={};bi.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;bi.size=payload+2*GUARD;bi.usage=VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
 CHECK(vkCreateBuffer(device,&bi,nullptr,&b.buffer));VkMemoryRequirements req;vkGetBufferMemoryRequirements(device,b.buffer,&req);
 uint32_t type=UINT32_MAX;for(uint32_t i=0;i<mem.memoryTypeCount;i++)if((req.memoryTypeBits&(1u<<i)) &&
 (mem.memoryTypes[i].propertyFlags&(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT))==(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)){type=i;break;}
 require(type!=UINT32_MAX,"coherent memory unavailable");VkMemoryAllocateInfo ma={};ma.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;ma.allocationSize=req.size;ma.memoryTypeIndex=type;
 CHECK(vkAllocateMemory(device,&ma,nullptr,&b.memory));CHECK(vkBindBufferMemory(device,b.buffer,b.memory,0));CHECK(vkMapMemory(device,b.memory,0,VK_WHOLE_SIZE,0,(void**)&b.bytes));
 memset(b.bytes,0xA5,payload+2*GUARD);memset(b.bytes+GUARD,0xCD,payload);return b;
}

int main(int argc,char** argv){
 if(argc!=6){fprintf(stderr,"usage: hdr-probe DRIVER SPV METALLIB INPUT OUTPUT_PREFIX\n");return 2;}
 auto input=read(argv[4]);require(input.size()%16==0 && input.size()/16<=131072,"row extent refused");uint32_t rows=uint32_t(input.size()/16);
 setenv("MVK_CONFIG_FAST_MATH_ENABLED","0",1);setenv("MVK_CONFIG_RESUME_LOST_DEVICE","0",1);
 void* lib=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(lib,"driver load failed");
#define LOAD(n) vk##n=(PFN_vk##n)dlsym(lib,"vk" #n);require(vk##n,"missing Vulkan function");
 FUNCTIONS(LOAD)
 VkApplicationInfo app={};app.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO;app.apiVersion=VK_API_VERSION_1_2;
 VkInstanceCreateInfo ii={};ii.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;ii.pApplicationInfo=&app;VkInstance instance;CHECK(vkCreateInstance(&ii,nullptr,&instance));
 uint32_t count=1;VkPhysicalDevice physical;CHECK(vkEnumeratePhysicalDevices(instance,&count,&physical));
 VkPhysicalDeviceProperties props;vkGetPhysicalDeviceProperties(physical,&props);printf("VULKAN device=%s driver=%u rows=%u fast_math=0 resume_lost_device=0\n",props.deviceName,props.driverVersion,rows);
 require(props.limits.minStorageBufferOffsetAlignment && GUARD%props.limits.minStorageBufferOffsetAlignment==0 && input.size()<=props.limits.maxStorageBufferRange && (rows+63)/64<=props.limits.maxComputeWorkGroupCount[0] && props.limits.maxComputeWorkGroupSize[0]>=64 && props.limits.maxComputeWorkGroupInvocations>=64,"device extent refused");
 uint32_t families=0;vkGetPhysicalDeviceQueueFamilyProperties(physical,&families,nullptr);std::vector<VkQueueFamilyProperties> qp(families);vkGetPhysicalDeviceQueueFamilyProperties(physical,&families,qp.data());
 uint32_t family=UINT32_MAX;for(uint32_t i=0;i<families;i++)if(qp[i].queueFlags&VK_QUEUE_COMPUTE_BIT){family=i;break;}require(family!=UINT32_MAX,"no compute queue");
 uint32_t ec=0;CHECK(vkEnumerateDeviceExtensionProperties(physical,nullptr,&ec,nullptr));std::vector<VkExtensionProperties> extensions(ec);CHECK(vkEnumerateDeviceExtensionProperties(physical,nullptr,&ec,extensions.data()));
 const char* portability=nullptr;for(auto& e:extensions)if(!strcmp(e.extensionName,"VK_KHR_portability_subset"))portability="VK_KHR_portability_subset";
 float priority=1;VkDeviceQueueCreateInfo qi={};qi.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;qi.queueFamilyIndex=family;qi.queueCount=1;qi.pQueuePriorities=&priority;
 VkPhysicalDeviceFeatures features={};features.robustBufferAccess=VK_TRUE;
 VkDeviceCreateInfo di={};di.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;di.queueCreateInfoCount=1;di.pQueueCreateInfos=&qi;di.pEnabledFeatures=&features;
 di.enabledExtensionCount=portability?1:0;di.ppEnabledExtensionNames=portability?&portability:nullptr;VkDevice device;CHECK(vkCreateDevice(physical,&di,nullptr,&device));
 VkQueue queue;vkGetDeviceQueue(device,family,0,&queue);VkPhysicalDeviceMemoryProperties memory;vkGetPhysicalDeviceMemoryProperties(physical,&memory);
 auto src=make_buffer(device,memory,input.size()),dst=make_buffer(device,memory,input.size());memcpy(src.bytes+GUARD,input.data(),input.size());
 VkDescriptorSetLayoutBinding binding[2]={};for(unsigned i=0;i<2;i++){binding[i].binding=i;binding[i].descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;binding[i].descriptorCount=1;binding[i].stageFlags=VK_SHADER_STAGE_COMPUTE_BIT;}
 VkDescriptorSetLayoutCreateInfo si={};si.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;si.bindingCount=2;si.pBindings=binding;VkDescriptorSetLayout sl;CHECK(vkCreateDescriptorSetLayout(device,&si,nullptr,&sl));
 VkPipelineLayoutCreateInfo li={};li.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;li.setLayoutCount=1;li.pSetLayouts=&sl;VkPipelineLayout layout;CHECK(vkCreatePipelineLayout(device,&li,nullptr,&layout));
 VkDescriptorPoolSize size={VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,2};VkDescriptorPoolCreateInfo pi={};pi.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;pi.maxSets=1;pi.poolSizeCount=1;pi.pPoolSizes=&size;VkDescriptorPool pool;CHECK(vkCreateDescriptorPool(device,&pi,nullptr,&pool));
 VkDescriptorSetAllocateInfo ai={};ai.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;ai.descriptorPool=pool;ai.descriptorSetCount=1;ai.pSetLayouts=&sl;VkDescriptorSet set;CHECK(vkAllocateDescriptorSets(device,&ai,&set));
 VkDescriptorBufferInfo buffer_info[2]={{src.buffer,GUARD,input.size()},{dst.buffer,GUARD,input.size()}};VkWriteDescriptorSet writes[2]={};
 for(unsigned i=0;i<2;i++){writes[i].sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;writes[i].dstSet=set;writes[i].dstBinding=i;writes[i].descriptorCount=1;writes[i].descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;writes[i].pBufferInfo=&buffer_info[i];}vkUpdateDescriptorSets(device,2,writes,0,nullptr);
 auto shader=read(argv[2]);require(shader.size()%4==0 && shader.size()>=20,"shader extent refused");VkShaderModuleCreateInfo sm={};sm.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;sm.codeSize=shader.size();sm.pCode=(const uint32_t*)shader.data();VkShaderModule module;CHECK(vkCreateShaderModule(device,&sm,nullptr,&module));
 VkComputePipelineCreateInfo ci={};ci.sType=VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;ci.layout=layout;ci.stage.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;ci.stage.stage=VK_SHADER_STAGE_COMPUTE_BIT;ci.stage.module=module;ci.stage.pName="main";VkPipeline pipeline;CHECK(vkCreateComputePipelines(device,VK_NULL_HANDLE,1,&ci,nullptr,&pipeline));
 VkCommandPoolCreateInfo cp={};cp.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;cp.queueFamilyIndex=family;VkCommandPool command_pool;CHECK(vkCreateCommandPool(device,&cp,nullptr,&command_pool));
 VkCommandBufferAllocateInfo ca={};ca.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;ca.commandPool=command_pool;ca.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY;ca.commandBufferCount=1;VkCommandBuffer command;CHECK(vkAllocateCommandBuffers(device,&ca,&command));
 VkCommandBufferBeginInfo begin={};begin.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;CHECK(vkBeginCommandBuffer(command,&begin));
 vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_COMPUTE,pipeline);vkCmdBindDescriptorSets(command,VK_PIPELINE_BIND_POINT_COMPUTE,layout,0,1,&set,0,nullptr);vkCmdDispatch(command,(rows+63)/64,1,1);
 VkMemoryBarrier mb={};mb.sType=VK_STRUCTURE_TYPE_MEMORY_BARRIER;mb.srcAccessMask=VK_ACCESS_SHADER_WRITE_BIT;mb.dstAccessMask=VK_ACCESS_HOST_READ_BIT;vkCmdPipelineBarrier(command,VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,VK_PIPELINE_STAGE_HOST_BIT,0,1,&mb,0,nullptr,0,nullptr);CHECK(vkEndCommandBuffer(command));
 VkFenceCreateInfo fi={};fi.sType=VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;VkFence fence;CHECK(vkCreateFence(device,&fi,nullptr,&fence));VkSubmitInfo submit={};submit.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO;submit.commandBufferCount=1;submit.pCommandBuffers=&command;CHECK(vkQueueSubmit(queue,1,&submit,fence));
 // Failure/timeout is terminal. No resource recycling, retries or further work.
 CHECK(vkWaitForFences(device,1,&fence,VK_TRUE,10000000000ull));guards(src.bytes,input.size());guards(dst.bytes,input.size());require(!memcmp(src.bytes+GUARD,input.data(),input.size()),"input modified");
 save(argv[5],".vulkan.bin",dst.bytes+GUARD,input.size());printf("VULKAN guards=intact input=unchanged\n");
 vkDestroyFence(device,fence,nullptr);vkDestroyCommandPool(device,command_pool,nullptr);vkDestroyPipeline(device,pipeline,nullptr);vkDestroyShaderModule(device,module,nullptr);vkDestroyDescriptorPool(device,pool,nullptr);vkDestroyPipelineLayout(device,layout,nullptr);vkDestroyDescriptorSetLayout(device,sl,nullptr);
 for(auto b:{src,dst}){vkUnmapMemory(device,b.memory);vkDestroyBuffer(device,b.buffer,nullptr);vkFreeMemory(device,b.memory,nullptr);}vkDestroyDevice(device,nullptr);vkDestroyInstance(instance,nullptr);
 @autoreleasepool {
  id<MTLDevice> metal=nil;for(id<MTLDevice> d in MTLCopyAllDevices())if(!strcmp(d.name.UTF8String,props.deviceName)){metal=d;break;}require(metal,"matching native Metal device unavailable");
  NSError* error=nil;id<MTLLibrary> library=[metal newLibraryWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[3]]] error:&error];require(library,"native library failed");
  id<MTLComputePipelineState> pso=[metal newComputePipelineStateWithFunction:[library newFunctionWithName:@"rosette_hdr_float16"] error:&error];require(pso,"native PSO failed");
  require(pso.maxTotalThreadsPerThreadgroup>=64,"native group extent refused");
  size_t bytes=input.size()+2*GUARD;id<MTLBuffer> a=[metal newBufferWithLength:bytes options:MTLResourceStorageModeShared],b=[metal newBufferWithLength:bytes options:MTLResourceStorageModeShared];require(a&&b,"native allocation failed");
  memset(a.contents,0xA5,bytes);memcpy((unsigned char*)a.contents+GUARD,input.data(),input.size());memset(b.contents,0xA5,bytes);memset((unsigned char*)b.contents+GUARD,0xCD,input.size());
  id<MTLCommandQueue> q=[metal newCommandQueue];id<MTLCommandBuffer> c=[q commandBuffer];require(q&&c,"native queue failed");id<MTLComputeCommandEncoder> e=[c computeCommandEncoder];require(e,"native encoder failed");
  [e setComputePipelineState:pso];[e setBuffer:a offset:GUARD atIndex:0];[e setBuffer:b offset:GUARD atIndex:1];[e setBytes:&rows length:4 atIndex:2];[e dispatchThreadgroups:MTLSizeMake((rows+63)/64,1,1) threadsPerThreadgroup:MTLSizeMake(64,1,1)];[e endEncoding];
  dispatch_group_t done=dispatch_group_create();dispatch_group_enter(done);[c addCompletedHandler:^(id<MTLCommandBuffer>){dispatch_group_leave(done);}];[c commit];
  require(dispatch_group_wait(done,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC))==0,"native completion timeout");require(c.status==MTLCommandBufferStatusCompleted,"native command failed");
  guards((unsigned char*)a.contents,input.size());guards((unsigned char*)b.contents,input.size());require(!memcmp((unsigned char*)a.contents+GUARD,input.data(),input.size()),"native input modified");
  save(argv[5],".metal.bin",(unsigned char*)b.contents+GUARD,input.size());printf("METAL device=%s guards=intact input=unchanged rows=%u\n",metal.name.UTF8String,rows);
 }
 return 0;
}
