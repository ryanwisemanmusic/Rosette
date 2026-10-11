// Native driver contract probe: no Xenia, Rosette guest, window, or long build.
// Checks Xenia's attachment-less mixed-MSAA FSI storage-buffer contract.
// FSI_PROBE_RECTANGLE_RECORD writes ten bounded 16x16 sample buffers for the
// independent rectangle precision comparison. That mode records, not asserts.
#define VK_NO_PROTOTYPES
#include "../../pkg/vendor/sources/vulkan-headers/1.4.313/include/vulkan/vulkan.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
 X(CmdPipelineBarrier) X(QueueSubmit) X(QueueWaitIdle)
#define DECLARE(n) static PFN_vk##n vk##n;
FUNCTIONS(DECLARE)
#define CHECK(e) do { VkResult r = (e); if (r != VK_SUCCESS) { \
 fprintf(stderr, "%s failed: %d\n", #e, r); exit(2); } } while (0)

static VkDevice device;
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

static VkPipeline pipeline(VkRenderPass pass, VkPipelineLayout layout,
 VkShaderModule vertex, VkShaderModule fragment, VkSampleCountFlagBits samples) {
 VkPipelineShaderStageCreateInfo stages[2] = {
  {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
   .stage=VK_SHADER_STAGE_VERTEX_BIT, .module=vertex, .pName="main"},
  {.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
   .stage=VK_SHADER_STAGE_FRAGMENT_BIT, .module=fragment, .pName="main"}};
 VkPipelineVertexInputStateCreateInfo vi = {.sType=VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
 VkPipelineInputAssemblyStateCreateInfo ia = {.sType=VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
  .topology=getenv("FSI_PROBE_RECTANGLE_RECORD")?VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP:VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST};
 VkViewport vp = {0,0,16,16,0,1}; VkRect2D sc = {{0,0},{16,16}};
 VkPipelineViewportStateCreateInfo vs = {.sType=VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
  .viewportCount=1,.pViewports=&vp,.scissorCount=1,.pScissors=&sc};
 VkPipelineRasterizationStateCreateInfo rs = {.sType=VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
  .polygonMode=VK_POLYGON_MODE_FILL,.cullMode=VK_CULL_MODE_NONE,.frontFace=VK_FRONT_FACE_COUNTER_CLOCKWISE,.lineWidth=1};
 VkPipelineMultisampleStateCreateInfo ms = {.sType=VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
  .rasterizationSamples=samples};
 VkPipelineColorBlendStateCreateInfo cb = {.sType=VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
 VkDynamicState dynamic_states[2]={VK_DYNAMIC_STATE_VIEWPORT,VK_DYNAMIC_STATE_SCISSOR};
 VkPipelineDynamicStateCreateInfo dynamic={.sType=VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,.dynamicStateCount=2,.pDynamicStates=dynamic_states};
 VkGraphicsPipelineCreateInfo info = {.sType=VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
  .stageCount=2,.pStages=stages,.pVertexInputState=&vi,.pInputAssemblyState=&ia,
  .pViewportState=&vs,.pRasterizationState=&rs,.pMultisampleState=&ms,
  .pColorBlendState=&cb,.pDynamicState=&dynamic,.layout=layout,.renderPass=pass};
 VkPipeline result; CHECK(vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, &info, NULL, &result)); return result;
}

int main(int argc, char **argv) {
 if (argc != 4) { fprintf(stderr,"usage: fsi-contract-probe DRIVER.dylib VERT.spv FRAG.spv\n"); return 2; }
 // Exactly the production precision setting; driver choice is explicit.
 setenv("MVK_CONFIG_FAST_MATH_ENABLED", "0", 1);
 void *lib=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL); if (!lib) { fprintf(stderr,"%s\n",dlerror());return 2; }
#define LOAD(n) vk##n=(PFN_vk##n)dlsym(lib,"vk" #n); if(!vk##n) { fprintf(stderr,"missing vk%s\n",#n);return 2; }
 FUNCTIONS(LOAD)
 VkApplicationInfo app = {.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.pApplicationName="Rosette FSI contract probe",.apiVersion=VK_API_VERSION_1_1};
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
 VkBufferCreateInfo bi={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,.size=16*16*4*4,.usage=VK_BUFFER_USAGE_STORAGE_BUFFER_BIT};VkBuffer buffer;
 CHECK(vkCreateBuffer(device,&bi,NULL,&buffer));VkMemoryRequirements req;vkGetBufferMemoryRequirements(device,buffer,&req);
 VkPhysicalDeviceMemoryProperties mem;vkGetPhysicalDeviceMemoryProperties(physical,&mem);uint32_t type=UINT32_MAX;
 for(uint32_t i=0;i<mem.memoryTypeCount;i++) if((req.memoryTypeBits&(1u<<i))&&
  (mem.memoryTypes[i].propertyFlags&(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT))==(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) {type=i;break;}
 if(type==UINT32_MAX)return 2;VkMemoryAllocateInfo ma={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=req.size,.memoryTypeIndex=type};VkDeviceMemory memory;
 CHECK(vkAllocateMemory(device,&ma,NULL,&memory));CHECK(vkBindBufferMemory(device,buffer,memory,0));uint32_t *pixels;
 CHECK(vkMapMemory(device,memory,0,VK_WHOLE_SIZE,0,(void**)&pixels));
 VkDescriptorSetLayoutBinding binding={.binding=0,.descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,.descriptorCount=1,.stageFlags=VK_SHADER_STAGE_FRAGMENT_BIT};
 VkDescriptorSetLayoutCreateInfo sl={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,.bindingCount=1,.pBindings=&binding};VkDescriptorSetLayout set_layout;
 CHECK(vkCreateDescriptorSetLayout(device,&sl,NULL,&set_layout));VkPushConstantRange push_range={VK_SHADER_STAGE_FRAGMENT_BIT,0,4};
 VkPipelineLayoutCreateInfo li={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,.setLayoutCount=1,.pSetLayouts=&set_layout,.pushConstantRangeCount=1,.pPushConstantRanges=&push_range};VkPipelineLayout layout;
 CHECK(vkCreatePipelineLayout(device,&li,NULL,&layout));VkDescriptorPoolSize ps={VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,1};
 VkDescriptorPoolCreateInfo pi={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,.maxSets=1,.poolSizeCount=1,.pPoolSizes=&ps};VkDescriptorPool pool;
 CHECK(vkCreateDescriptorPool(device,&pi,NULL,&pool));VkDescriptorSetAllocateInfo sa={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,.descriptorPool=pool,.descriptorSetCount=1,.pSetLayouts=&set_layout};VkDescriptorSet set;
 CHECK(vkAllocateDescriptorSets(device,&sa,&set));VkDescriptorBufferInfo db={buffer,0,bi.size};VkWriteDescriptorSet write={.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=set,.descriptorCount=1,.descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,.pBufferInfo=&db};vkUpdateDescriptorSets(device,1,&write,0,NULL);
 VkSubpassDescription sub={.pipelineBindPoint=VK_PIPELINE_BIND_POINT_GRAPHICS};
 VkSubpassDependency deps[2]={{VK_SUBPASS_EXTERNAL,0,VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,VK_ACCESS_SHADER_READ_BIT|VK_ACCESS_SHADER_WRITE_BIT,VK_ACCESS_SHADER_READ_BIT|VK_ACCESS_SHADER_WRITE_BIT,VK_DEPENDENCY_BY_REGION_BIT},
  {0,VK_SUBPASS_EXTERNAL,VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,VK_ACCESS_SHADER_READ_BIT|VK_ACCESS_SHADER_WRITE_BIT,VK_ACCESS_SHADER_READ_BIT|VK_ACCESS_SHADER_WRITE_BIT,VK_DEPENDENCY_BY_REGION_BIT}};
 VkRenderPassCreateInfo ri={.sType=VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,.subpassCount=1,.pSubpasses=&sub,.dependencyCount=2,.pDependencies=deps};
 VkCommandPoolCreateInfo cp={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,.flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,.queueFamilyIndex=family};VkCommandPool command_pool;
 CHECK(vkCreateCommandPool(device,&cp,NULL,&command_pool));VkCommandBufferAllocateInfo ca={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,.commandPool=command_pool,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};VkCommandBuffer command;
 CHECK(vkAllocateCommandBuffers(device,&ca,&command));VkShaderModule vert=module(argv[2]),frag=module(argv[3]);int failures=0;
 const char *record_path=getenv("FSI_PROBE_RECTANGLE_RECORD");FILE *record=NULL;
 if(record_path) {record=fopen(record_path,"wb");if(!record) {perror(record_path);return 2;}}
 for(unsigned order=0;order<2;order++) {
  VkRenderPass pass;CHECK(vkCreateRenderPass(device,&ri,NULL,&pass));
  int isolate=getenv("FSI_PROBE_ISOLATE_SAMPLES")!=NULL;
  VkRenderPass aliases[2]={pass,pass};
  if(isolate) CHECK(vkCreateRenderPass(device,&ri,NULL,&aliases[1]));
  VkFramebufferCreateInfo fi={.sType=VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,.renderPass=pass,.width=16,.height=16,.layers=1};VkFramebuffer fb;
  CHECK(vkCreateFramebuffer(device,&fi,NULL,&fb));VkPipeline pipelines[2];
  for(unsigned i=0;i<2;i++) { unsigned index=i^order;pipelines[index]=pipeline(aliases[index],layout,vert,frag,index?VK_SAMPLE_COUNT_4_BIT:VK_SAMPLE_COUNT_1_BIT); }
  for(unsigned mode=0;mode<5;mode++) {
   memset(pixels,0,(size_t)bi.size);CHECK(vkResetCommandBuffer(command,0));VkCommandBufferBeginInfo begin={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};CHECK(vkBeginCommandBuffer(command,&begin));
   unsigned active=(mode==1 || mode==4)?1:0;
   // Bind once, including dynamic state and push constants, before the pass.
   // The adaptation relies on these surviving same-command-buffer restarts.
   VkViewport viewport={0,0,16,16,0,1};VkRect2D scissor={{0,0},{16,16}};uint32_t amount=1;
   vkCmdSetViewport(command,0,1,&viewport);vkCmdSetScissor(command,0,1,&scissor);
   vkCmdPushConstants(command,layout,VK_SHADER_STAGE_FRAGMENT_BIT,0,4,&amount);
   vkCmdBindDescriptorSets(command,VK_PIPELINE_BIND_POINT_GRAPHICS,layout,0,1,&set,0,NULL);
   vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_GRAPHICS,pipelines[active]);
   VkRenderPassBeginInfo rb={.sType=VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,.renderPass=aliases[active],.framebuffer=fb,.renderArea={{0,0},{16,16}}};vkCmdBeginRenderPass(command,&rb,VK_SUBPASS_CONTENTS_INLINE);
   unsigned expected[4]={0};
   for(unsigned draw=0;draw<37;draw++) {
    unsigned index=mode==0?0:(mode==1 || mode==4)?1:draw%2;
    if(draw && (mode==3 || mode==4 || (isolate && active!=index))) {vkCmdEndRenderPass(command);rb.renderPass=aliases[index];vkCmdBeginRenderPass(command,&rb,VK_SUBPASS_CONTENTS_INLINE);}
    if(active!=index) vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_GRAPHICS,pipelines[index]);
    active=index;
    vkCmdDraw(command,record?4:3,1,record&&getenv("FSI_PROBE_RECTANGLE_TAG")?0x80000000u:0,0);
    expected[0]++;if(index)for(unsigned s=1;s<4;s++)expected[s]++;
   }
   vkCmdEndRenderPass(command);VkMemoryBarrier mb={.sType=VK_STRUCTURE_TYPE_MEMORY_BARRIER,.srcAccessMask=VK_ACCESS_SHADER_WRITE_BIT,.dstAccessMask=VK_ACCESS_HOST_READ_BIT};vkCmdPipelineBarrier(command,VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,VK_PIPELINE_STAGE_HOST_BIT,0,1,&mb,0,NULL,0,NULL);
   CHECK(vkEndCommandBuffer(command));VkSubmitInfo submit={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&command};CHECK(vkQueueSubmit(queue,1,&submit,VK_NULL_HANDLE));CHECK(vkQueueWaitIdle(queue));
   const char *mode_name=(const char*[]){"1x","4x","mixed","mixed_restart","4x_restart_without_rebind"}[mode];
   if(record) {
    if(fwrite(pixels,1,(size_t)bi.size,record)!=(size_t)bi.size)return 2;
    printf("RECORDED isolated=%d last_pipeline=%ux mode=%s bytes=%llu\n",isolate,order?1:4,mode_name,(unsigned long long)bi.size);
   } else {
    unsigned wrong=0;for(unsigned p=0;p<16*16;p++)for(unsigned s=0;s<4;s++)wrong+=pixels[p*4+s]!=expected[s];
    printf("isolated=%d last_pipeline=%ux mode=%s wrong=%u/1024 first=%u,%u,%u,%u expected=%u,%u,%u,%u %s\n",isolate,order?1:4,mode_name,wrong,pixels[0],pixels[1],pixels[2],pixels[3],expected[0],expected[1],expected[2],expected[3],wrong?"FAIL":"PASS");failures+=wrong!=0;
   }
  }
  for(unsigned i=0;i<2;i++)vkDestroyPipeline(device,pipelines[i],NULL);vkDestroyFramebuffer(device,fb,NULL);if(isolate)vkDestroyRenderPass(device,aliases[1],NULL);vkDestroyRenderPass(device,pass,NULL);
 }
 if(record && fclose(record))return 2;
 vkDestroyShaderModule(device,vert,NULL);vkDestroyShaderModule(device,frag,NULL);vkDestroyCommandPool(device,command_pool,NULL);
 vkDestroyDescriptorPool(device,pool,NULL);vkDestroyPipelineLayout(device,layout,NULL);vkDestroyDescriptorSetLayout(device,set_layout,NULL);
 vkUnmapMemory(device,memory);vkDestroyBuffer(device,buffer,NULL);vkFreeMemory(device,memory,NULL);vkDestroyDevice(device,NULL);vkDestroyInstance(instance,NULL);dlclose(lib);return failures?1:0;
}
