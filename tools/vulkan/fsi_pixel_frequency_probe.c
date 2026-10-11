// Native driver contract probe: no Xenia, Rosette guest, window, or long build.
// Checks Xenia's attachment-less mixed-MSAA FSI storage-buffer contract.
// Pixel-center coordinates, depth, coverage and repeated ordered updates.
// Synthetic data only; bounded shader addresses; finite fence wait; guard bytes.
#define VK_NO_PROTOTYPES
#include "../../pkg/vendor/sources/vulkan-headers/1.4.313/include/vulkan/vulkan.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define FUNCTIONS(X) \
 X(CreateInstance) X(DestroyInstance) X(EnumeratePhysicalDevices) \
 X(GetPhysicalDeviceProperties) X(GetPhysicalDeviceFeatures2) \
 X(GetPhysicalDeviceMemoryProperties) X(GetPhysicalDeviceQueueFamilyProperties) \
 X(EnumerateDeviceExtensionProperties) X(CreateDevice) X(DestroyDevice) X(GetDeviceQueue) \
 X(CreateBuffer) X(DestroyBuffer) X(GetBufferMemoryRequirements) X(AllocateMemory) \
 X(FreeMemory) X(BindBufferMemory) X(MapMemory) X(UnmapMemory) \
 X(CreateDescriptorSetLayout) X(DestroyDescriptorSetLayout) X(CreatePipelineLayout) \
 X(DestroyPipelineLayout) X(CreateDescriptorPool) X(DestroyDescriptorPool) \
 X(AllocateDescriptorSets) X(UpdateDescriptorSets) X(CreateShaderModule) \
 X(DestroyShaderModule) X(CreateRenderPass) X(DestroyRenderPass) X(CreateFramebuffer) \
 X(DestroyFramebuffer) X(CreateGraphicsPipelines) X(DestroyPipeline) \
 X(CreateCommandPool) X(DestroyCommandPool) X(AllocateCommandBuffers) \
 X(ResetCommandBuffer) X(BeginCommandBuffer) X(EndCommandBuffer) X(CmdBeginRenderPass) \
 X(CmdEndRenderPass) X(CmdBindPipeline) X(CmdBindDescriptorSets) X(CmdDraw) \
 X(CmdSetViewport) X(CmdSetScissor) X(CmdPushConstants) \
 X(CmdPipelineBarrier) X(QueueSubmit) X(CreateFence) X(DestroyFence) X(WaitForFences) X(ResetFences)
#define DECLARE(n) static PFN_vk##n vk##n;
FUNCTIONS(DECLARE)
#define CHECK(e) do { VkResult r = (e); if (r != VK_SUCCESS) { \
 fprintf(stderr, "%s failed: %d\n", #e, r); exit(2); } } while (0)

static VkDevice device;
static VkPipeline pipeline(VkRenderPass pass, VkPipelineLayout layout, VkShaderModule vertex,
 VkShaderModule fragment, VkSampleCountFlagBits samples, uint32_t mask) {
 VkPipelineShaderStageCreateInfo stages[2]={
  {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_VERTEX_BIT,.module=vertex,.pName="main"},
  {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_FRAGMENT_BIT,.module=fragment,.pName="main"}};
 VkPipelineVertexInputStateCreateInfo vi={.sType=VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
 VkPipelineInputAssemblyStateCreateInfo ia={.sType=VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,.topology=VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST};
 VkViewport vp={0,0,16,16,0,1};VkRect2D sc={{0,0},{16,16}};
 VkPipelineViewportStateCreateInfo vs={.sType=VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,.viewportCount=1,.pViewports=&vp,.scissorCount=1,.pScissors=&sc};
 VkPipelineRasterizationStateCreateInfo rs={.sType=VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,.polygonMode=VK_POLYGON_MODE_FILL,.cullMode=VK_CULL_MODE_NONE,.frontFace=VK_FRONT_FACE_COUNTER_CLOCKWISE,.lineWidth=1};
 VkPipelineMultisampleStateCreateInfo ms={.sType=VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,.rasterizationSamples=samples,.pSampleMask=&mask};
 VkPipelineColorBlendStateCreateInfo cb={.sType=VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
 VkGraphicsPipelineCreateInfo info={.sType=VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,.stageCount=2,.pStages=stages,
  .pVertexInputState=&vi,.pInputAssemblyState=&ia,.pViewportState=&vs,.pRasterizationState=&rs,.pMultisampleState=&ms,
  .pColorBlendState=&cb,.layout=layout,.renderPass=pass};
 VkPipeline result;CHECK(vkCreateGraphicsPipelines(device,VK_NULL_HANDLE,1,&info,NULL,&result));return result;
}
static VkShaderModule module(const char *path) {
 FILE *f = fopen(path, "rb"); if (!f) { perror(path); exit(2); }
 fseek(f, 0, SEEK_END); long size = ftell(f); rewind(f);
 if (size < 20 || size % 4) exit(2);
 uint32_t *code = malloc((size_t)size); if (!code) exit(2);
 if (fread(code, 1, (size_t)size, f) != (size_t)size) exit(2); fclose(f);
 VkShaderModuleCreateInfo info = {.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
  .codeSize=(size_t)size, .pCode=code}; VkShaderModule result;
 CHECK(vkCreateShaderModule(device, &info, NULL, &result)); free(code); return result;
}

int main(int argc, char **argv) {
 if (argc != 5) { fprintf(stderr,"usage: fsi-pixel-probe DRIVER.dylib VERT.spv ORIGINAL.spv NORMALIZED.spv\n"); return 2; }
 // Exactly the production precision setting; driver choice is explicit.
 setenv("MVK_CONFIG_FAST_MATH_ENABLED", "0", 1);
 void *lib=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL); if (!lib) { fprintf(stderr,"%s\n",dlerror());return 2; }
#define LOAD(n) vk##n=(PFN_vk##n)dlsym(lib,"vk" #n); if(!vk##n) { fprintf(stderr,"missing vk%s\n",#n);return 2; }
 FUNCTIONS(LOAD)
 VkApplicationInfo app = {.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.pApplicationName="Rosette FSI contract probe",.apiVersion=VK_API_VERSION_1_2};
 VkInstanceCreateInfo ii = {.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&app}; VkInstance instance;
 CHECK(vkCreateInstance(&ii,NULL,&instance)); uint32_t count=1; VkPhysicalDevice physical;
 CHECK(vkEnumeratePhysicalDevices(instance,&count,&physical));
 VkPhysicalDeviceProperties props;vkGetPhysicalDeviceProperties(physical,&props);
 printf("driver=%s device=%s driverVersion=%u\n",argv[1],props.deviceName,props.driverVersion);
 VkPhysicalDeviceFragmentShaderInterlockFeaturesEXT interlock = {.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_INTERLOCK_FEATURES_EXT};
 VkPhysicalDeviceFeatures2 features={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,.pNext=&interlock};
 vkGetPhysicalDeviceFeatures2(physical,&features);
 if(!interlock.fragmentShaderSampleInterlock || !features.features.fragmentStoresAndAtomics) { fprintf(stderr,"FSI prerequisites missing\n");return 2; }
 interlock.fragmentShaderPixelInterlock=VK_FALSE;interlock.fragmentShaderShadingRateInterlock=VK_FALSE;
 VkPhysicalDeviceFeatures enabled={.fragmentStoresAndAtomics=VK_TRUE,.sampleRateShading=VK_TRUE};
 const char *extensions[2]={VK_EXT_FRAGMENT_SHADER_INTERLOCK_EXTENSION_NAME}; uint32_t extension_count=1, ext_count=0;
 CHECK(vkEnumerateDeviceExtensionProperties(physical,NULL,&ext_count,NULL));
 VkExtensionProperties *exts=calloc(ext_count,sizeof(*exts));CHECK(vkEnumerateDeviceExtensionProperties(physical,NULL,&ext_count,exts));
 for(uint32_t i=0;i<ext_count;i++) if(!strcmp(exts[i].extensionName,"VK_KHR_portability_subset")) extensions[extension_count++]="VK_KHR_portability_subset";
 free(exts);
 uint32_t qc=0;vkGetPhysicalDeviceQueueFamilyProperties(physical,&qc,NULL);VkQueueFamilyProperties *qps=calloc(qc,sizeof(*qps));
 vkGetPhysicalDeviceQueueFamilyProperties(physical,&qc,qps);uint32_t family=UINT32_MAX;
 for(uint32_t i=0;i<qc;i++) if(qps[i].queueFlags&VK_QUEUE_GRAPHICS_BIT) { family=i;break; } free(qps);if(family==UINT32_MAX)return 2;
 float priority=1;VkDeviceQueueCreateInfo qi={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,.queueFamilyIndex=family,.queueCount=1,.pQueuePriorities=&priority};
 VkDeviceCreateInfo di={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.pNext=&interlock,.queueCreateInfoCount=1,.pQueueCreateInfos=&qi,
  .enabledExtensionCount=extension_count,.ppEnabledExtensionNames=extensions,.pEnabledFeatures=&enabled};
 CHECK(vkCreateDevice(physical,&di,NULL,&device));VkQueue queue;vkGetDeviceQueue(device,family,0,&queue);
 const size_t data_size=16*16*4*16+16*16*4, guard_size=256, total_size=data_size+2*guard_size;
 VkBufferCreateInfo bi={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,.size=total_size,.usage=VK_BUFFER_USAGE_STORAGE_BUFFER_BIT};VkBuffer buffer;
 CHECK(vkCreateBuffer(device,&bi,NULL,&buffer));VkMemoryRequirements req;vkGetBufferMemoryRequirements(device,buffer,&req);
 VkPhysicalDeviceMemoryProperties mem;vkGetPhysicalDeviceMemoryProperties(physical,&mem);uint32_t type=UINT32_MAX;
 for(uint32_t i=0;i<mem.memoryTypeCount;i++) if((req.memoryTypeBits&(1u<<i))&&
  (mem.memoryTypes[i].propertyFlags&(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT))==(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) {type=i;break;}
 if(type==UINT32_MAX)return 2;
 VkMemoryAllocateInfo ma={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=req.size,.memoryTypeIndex=type};VkDeviceMemory memory;
 CHECK(vkAllocateMemory(device,&ma,NULL,&memory));CHECK(vkBindBufferMemory(device,buffer,memory,0));unsigned char *mapped;
 CHECK(vkMapMemory(device,memory,0,VK_WHOLE_SIZE,0,(void**)&mapped));uint32_t *pixels=(uint32_t*)(mapped+guard_size);
 VkDescriptorSetLayoutBinding binding={.binding=0,.descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,.descriptorCount=1,.stageFlags=VK_SHADER_STAGE_FRAGMENT_BIT};
 VkDescriptorSetLayoutCreateInfo sl={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,.bindingCount=1,.pBindings=&binding};VkDescriptorSetLayout set_layout;
 CHECK(vkCreateDescriptorSetLayout(device,&sl,NULL,&set_layout));
 VkPipelineLayoutCreateInfo li={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,.setLayoutCount=1,.pSetLayouts=&set_layout};VkPipelineLayout layout;
 CHECK(vkCreatePipelineLayout(device,&li,NULL,&layout));VkDescriptorPoolSize ps={VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,1};
 VkDescriptorPoolCreateInfo pi={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,.maxSets=1,.poolSizeCount=1,.pPoolSizes=&ps};VkDescriptorPool pool;
 CHECK(vkCreateDescriptorPool(device,&pi,NULL,&pool));VkDescriptorSetAllocateInfo sa={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,.descriptorPool=pool,.descriptorSetCount=1,.pSetLayouts=&set_layout};VkDescriptorSet set;
 CHECK(vkAllocateDescriptorSets(device,&sa,&set));VkDescriptorBufferInfo db={buffer,guard_size,data_size};
 VkWriteDescriptorSet write={.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=set,.descriptorCount=1,.descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,.pBufferInfo=&db};vkUpdateDescriptorSets(device,1,&write,0,NULL);
 VkSubpassDescription sub={.pipelineBindPoint=VK_PIPELINE_BIND_POINT_GRAPHICS};
 VkSubpassDependency deps[2]={{VK_SUBPASS_EXTERNAL,0,VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,VK_ACCESS_SHADER_WRITE_BIT,VK_ACCESS_SHADER_READ_BIT|VK_ACCESS_SHADER_WRITE_BIT,VK_DEPENDENCY_BY_REGION_BIT},
  {0,VK_SUBPASS_EXTERNAL,VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,VK_ACCESS_SHADER_WRITE_BIT,VK_ACCESS_SHADER_READ_BIT|VK_ACCESS_SHADER_WRITE_BIT,VK_DEPENDENCY_BY_REGION_BIT}};
 VkRenderPassCreateInfo ri={.sType=VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,.subpassCount=1,.pSubpasses=&sub,.dependencyCount=2,.pDependencies=deps};
 VkCommandPoolCreateInfo cp={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,.flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,.queueFamilyIndex=family};VkCommandPool command_pool;
 CHECK(vkCreateCommandPool(device,&cp,NULL,&command_pool));VkCommandBufferAllocateInfo ca={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,.commandPool=command_pool,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};VkCommandBuffer command;
 CHECK(vkAllocateCommandBuffers(device,&ca,&command));
 VkFenceCreateInfo fence_info={.sType=VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};VkFence fence;CHECK(vkCreateFence(device,&fence_info,NULL,&fence));
 VkShaderModule vert=module(argv[2]),frag[2]={module(argv[3]),module(argv[4])};unsigned passed=0,negative_detected=0;
 uint32_t *reference_z=calloc(24*1024,sizeof(uint32_t));if(!reference_z)return 2;
 for(unsigned order=0;order<2;order++) {
  // Distinct render-pass identities: prevent a driver's sample-count cache from aliasing them.
  VkRenderPass pass[3];VkFramebuffer fb[3];VkPipeline pipelines[2][3][2];
  for(unsigned creation=0;creation<3;creation++) {
   unsigned n=order?2-creation:creation;
   CHECK(vkCreateRenderPass(device,&ri,NULL,&pass[n]));
   VkFramebufferCreateInfo fi={.sType=VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,.renderPass=pass[n],.width=16,.height=16,.layers=1};CHECK(vkCreateFramebuffer(device,&fi,NULL,&fb[n]));
   for(unsigned v=0;v<2;v++)for(unsigned m=0;m<2;m++) {
    pipelines[v][n][m]=pipeline(pass[n],layout,vert,frag[v],(VkSampleCountFlagBits)(1u<<n),m?5u:15u);
   }
  }
  for(unsigned v=0;v<2;v++)for(unsigned n=0;n<3;n++)for(unsigned m=0;m<2;m++)for(unsigned repetition=0;repetition<2;repetition++) {
   memset(mapped,0xA5,total_size);memset(pixels,0,data_size);CHECK(vkResetCommandBuffer(command,0));
   VkCommandBufferBeginInfo begin={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};CHECK(vkBeginCommandBuffer(command,&begin));
   vkCmdBindDescriptorSets(command,VK_PIPELINE_BIND_POINT_GRAPHICS,layout,0,1,&set,0,NULL);
   vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_GRAPHICS,pipelines[v][n][m]);
   unsigned draws=repetition?7:1;
   for(unsigned draw=0;draw<draws;draw++) {
    VkRenderPassBeginInfo rb={.sType=VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,.renderPass=pass[n],.framebuffer=fb[n],.renderArea={{0,0},{16,16}}};
    vkCmdBeginRenderPass(command,&rb,VK_SUBPASS_CONTENTS_INLINE);vkCmdDraw(command,3,1,0,0);vkCmdEndRenderPass(command);
   }
   VkMemoryBarrier mb={.sType=VK_STRUCTURE_TYPE_MEMORY_BARRIER,.srcAccessMask=VK_ACCESS_SHADER_WRITE_BIT,.dstAccessMask=VK_ACCESS_HOST_READ_BIT};
   vkCmdPipelineBarrier(command,VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,VK_PIPELINE_STAGE_HOST_BIT,0,1,&mb,0,NULL,0,NULL);
   CHECK(vkEndCommandBuffer(command));VkSubmitInfo submit={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&command};
   CHECK(vkQueueSubmit(queue,1,&submit,fence));
   // A failed/timeout wait ends the process. Never recycle or free resources from failed work.
   CHECK(vkWaitForFences(device,1,&fence,VK_TRUE,10000000000ull));CHECK(vkResetFences(device,1,&fence));
   for(size_t i=0;i<guard_size;i++)if(mapped[i]!=0xA5 || mapped[guard_size+data_size+i]!=0xA5) {fprintf(stderr,"GUARD CORRUPTION\n");return 2;}
   unsigned xy_bad=0,z_bad=0,z_parity_bad=0,count_bad=0,invocation_bad=0;float first[3]={0};
   unsigned case_index=((order*3+n)*2+m)*2+repetition;
   uint32_t *invocations=pixels+4096;
   // The driver still invokes the old sample-frequency shader at masked-off
   // samples (zero input coverage). Count executions separately from writes.
   for(unsigned p=0;p<256;p++)invocation_bad+=invocations[p]!=draws*(1u<<n);
   for(unsigned y=0;y<16;y++)for(unsigned x=0;x<16;x++)for(unsigned s=0;s<4;s++) {
    uint32_t *p=pixels+((y*16+x)*4+s)*4;
    unsigned covered=s<(1u<<n) && (((m?5u:15u)>>s)&1u);
    if(p[3]!=(covered?draws:0))count_bad++;
    if(covered) {
     float f[3];memcpy(f,p,sizeof(f));if(x==0 && y==0 && s==0)memcpy(first,f,sizeof(f));
     // Centers are exact; raster depth interpolation may round by a few ULPs.
     // Verify finite CPU-plane proximity and exact old/new depth bit parity.
     xy_bad+=f[0]!=(x+0.5f) || f[1]!=(y+0.5f);
     z_bad+=!isfinite(f[2]) || fabsf(f[2]-(0.125f+(x+0.5f)/64.f+(y+0.5f)/128.f))>0.000002f;
     unsigned zi=case_index*1024+(y*16+x)*4+s;
     if(v)z_parity_bad+=reference_z[zi]!=p[2];else reference_z[zi]=p[2];
    } else if(p[0] || p[1] || p[2]) {fprintf(stderr,"UNTOUCHED SAMPLE CHANGED\n");return 2;}
   }
   printf("CASE normalized=%u order=%u samples=%u mask=%u draws=%u xy_bad=%u z_bad=%u z_parity_bad=%u count_bad=%u invocation_bad=%u invocations_first=%u first=%g,%g,%g guards=intact\n",v,order,1u<<n,m?5u:15u,draws,xy_bad,z_bad,z_parity_bad,count_bad,invocation_bad,invocations[0],first[0],first[1],first[2]);
   if(invocation_bad || count_bad)return 1;
   if(v && (xy_bad || z_bad || z_parity_bad))return 1;
   if(v)passed++;else if(xy_bad || z_bad)negative_detected++;
  }
  for(unsigned n=0;n<3;n++) {
   for(unsigned v=0;v<2;v++)for(unsigned m=0;m<2;m++)vkDestroyPipeline(device,pipelines[v][n][m],NULL);
   vkDestroyFramebuffer(device,fb[n],NULL);vkDestroyRenderPass(device,pass[n],NULL);
  }
 }
 printf("RESULT normalized_passes=%u negative_controls_detected=%u\n",passed,negative_detected);
 if(!negative_detected)return 1;
 free(reference_z);
 for(unsigned v=0;v<2;v++)vkDestroyShaderModule(device,frag[v],NULL);vkDestroyShaderModule(device,vert,NULL);
 vkDestroyFence(device,fence,NULL);vkDestroyCommandPool(device,command_pool,NULL);vkDestroyDescriptorPool(device,pool,NULL);
 vkDestroyPipelineLayout(device,layout,NULL);vkDestroyDescriptorSetLayout(device,set_layout,NULL);
 vkUnmapMemory(device,memory);vkDestroyBuffer(device,buffer,NULL);vkFreeMemory(device,memory,NULL);
 vkDestroyDevice(device,NULL);vkDestroyInstance(instance,NULL);dlclose(lib);return 0;
}
