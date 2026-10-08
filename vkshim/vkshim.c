/*
 * libMoltenVK.dylib stand-in for the NotProton CrossOver runner.
 *
 * Wine's win32u dlopen()s "libMoltenVK.dylib" and only looks up
 * vkGetInstanceProcAddr. This shim forwards that to either:
 *   - KosmicKrisp (Mesa Vulkan-on-Metal4), when the Wine prefix opts in by
 *     having a "notproton-kosmickrisp" file next to it
 *     (steamapps/compatdata/<appid>/notproton-kosmickrisp), or when
 *     NOTPROTON_VK_DRIVER=kosmickrisp is set;
 *   - the original MoltenVK (libMoltenVK.real.dylib) otherwise.
 */
#include <dlfcn.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <mach-o/dyld.h>

/* NOTPROTON_VKSHIM_IMAGES=1 logs every loaded image with its load address,
 * to map native crash addresses back to modules. */
static void log_image(const struct mach_header *mh, intptr_t slide)
{
    Dl_info info;
    (void)slide;
    if (dladdr(mh, &info) && info.dli_fname)
        fprintf(stderr, "vkshim: image %p %s\n", (void *)mh, info.dli_fname);
}

typedef void (*PFN_vkVoidFunction)(void);
typedef PFN_vkVoidFunction (*PFN_gipa)(void *instance, const char *name);
typedef int (*PFN_negotiate)(unsigned int *version);

static PFN_gipa real_gipa;
static int using_kk;
static pthread_once_t once = PTHREAD_ONCE_INIT;

static int want_kosmickrisp(void)
{
    const char *env = getenv("NOTPROTON_VK_DRIVER");
    if (env)
        return strcmp(env, "kosmickrisp") == 0;

    const char *prefix = getenv("WINEPREFIX");
    if (!prefix || !*prefix)
        return 0;
    char flag[PATH_MAX];
    snprintf(flag, sizeof(flag), "%s/../notproton-kosmickrisp", prefix);
    return access(flag, F_OK) == 0;
}

static void init(void)
{
    Dl_info info;
    char dir[PATH_MAX], path[PATH_MAX];

    if (!dladdr((void *)init, &info) || !info.dli_fname)
        return;
    snprintf(dir, sizeof(dir), "%s", info.dli_fname);
    char *slash = strrchr(dir, '/');
    if (slash)
        *slash = 0;

    if (want_kosmickrisp()) {
        snprintf(path, sizeof(path), "%s/kosmickrisp/libvulkan_kosmickrisp.dylib", dir);
        void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
        if (h) {
            PFN_negotiate negotiate =
                (PFN_negotiate)dlsym(h, "vk_icdNegotiateLoaderICDInterfaceVersion");
            if (negotiate) {
                unsigned int version = 5;
                negotiate(&version);
            }
            real_gipa = (PFN_gipa)dlsym(h, "vk_icdGetInstanceProcAddr");
            if (real_gipa) {
                using_kk = 1;
                if (getenv("NOTPROTON_VKSHIM_IMAGES") || access("/tmp/vkshim-images", F_OK) == 0)
                    _dyld_register_func_for_add_image(log_image);
                Dl_info kk_info = {0};
                dladdr((void *)real_gipa, &kk_info);
                fprintf(stderr, "vkshim: using KosmicKrisp (%s) base=%p\n", path, kk_info.dli_fbase);
                return;
            }
        }
        fprintf(stderr, "vkshim: KosmicKrisp unavailable (%s), falling back to MoltenVK\n",
                dlerror());
    }

    snprintf(path, sizeof(path), "%s/libMoltenVK.real.dylib", dir);
    void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (h)
        real_gipa = (PFN_gipa)dlsym(h, "vkGetInstanceProcAddr");
    if (!real_gipa)
        fprintf(stderr, "vkshim: failed to load MoltenVK (%s)\n", dlerror());
}

/* Mesa only resolves global commands for a NULL instance, so remember the
 * last instance seen to resolve vkGetDeviceProcAddr through it. */
static void *volatile last_instance;

/* CrossOver 26.3's winevulkan predates Vulkan 1.4 and returns NULL for
 * 1.4 core entry points (vkCmdPushDescriptorSet, ...). KosmicKrisp reports
 * 1.4, so clamp the device apiVersion to 1.3 to make apps fall back to the
 * KHR/EXT names Wine knows. */
#define API_1_3 ((1u << 22) | (3u << 12))
#define API_MAX API_1_3

typedef struct { unsigned int sType; void *pNext; unsigned char properties[]; } props2_t;
typedef void (*PFN_props)(void *pd, void *props);

static PFN_props real_props, real_props2, real_props2khr;

static void clamp_api(unsigned int *api)
{
    if (*api > API_MAX)
        *api = API_MAX;
}

static void shim_props(void *pd, void *props)
{
    real_props(pd, props);
    clamp_api((unsigned int *)props); /* apiVersion is the first member */
}

static void shim_props2(void *pd, void *props)
{
    real_props2(pd, props);
    clamp_api((unsigned int *)((props2_t *)props)->properties);
}

static void shim_props2khr(void *pd, void *props)
{
    real_props2khr(pd, props);
    clamp_api((unsigned int *)((props2_t *)props)->properties);
}

static PFN_vkVoidFunction wrap_props(void *instance, const char *name, PFN_vkVoidFunction fn)
{
    if (!fn || !using_kk)
        return fn;
    if (!strcmp(name, "vkGetPhysicalDeviceProperties")) {
        real_props = (PFN_props)fn;
        return (PFN_vkVoidFunction)shim_props;
    }
    if (!strcmp(name, "vkGetPhysicalDeviceProperties2")) {
        real_props2 = (PFN_props)fn;
        return (PFN_vkVoidFunction)shim_props2;
    }
    if (!strcmp(name, "vkGetPhysicalDeviceProperties2KHR")) {
        real_props2khr = (PFN_props)fn;
        return (PFN_vkVoidFunction)shim_props2khr;
    }
    (void)instance;
    return fn;
}

/* Mesa only resolves instance commands of enabled extensions, while MoltenVK
 * resolves them all. Wine probes vkCreateMetalSurfaceEXT on its host instance
 * without enabling VK_EXT_metal_surface, then hides VK_KHR_win32_surface from
 * Windows apps. Always enable the surface extensions on KosmicKrisp. */
typedef struct {
    unsigned int sType;
    const void *pNext;
    unsigned int flags;
    const void *pApplicationInfo;
    unsigned int enabledLayerCount;
    const char *const *ppEnabledLayerNames;
    unsigned int enabledExtensionCount;
    const char *const *ppEnabledExtensionNames;
} instance_info_t;
typedef int (*PFN_create_instance)(const instance_info_t *info, const void *alloc, void **instance);

static PFN_create_instance real_create_instance;

typedef struct {
    unsigned int sType;
    const void *pNext;
    const char *pApplicationName;
    unsigned int applicationVersion;
    const char *pEngineName;
    unsigned int engineVersion;
    unsigned int apiVersion;
} app_info_t;
typedef struct { char extensionName[256]; unsigned int specVersion; } ext_props_t;
typedef int (*PFN_enum_instance_ext)(const char *layer, unsigned int *count, ext_props_t *props);

#define STYPE_APPLICATION_INFO 0

/* Like MoltenVK, expose everything: enable every instance extension the
 * driver has and request at least Vulkan 1.3, so Mesa resolves all the
 * instance commands Wine looks up. */
static int shim_create_instance(const instance_info_t *info, const void *alloc, void **instance)
{
    static ext_props_t props[128];
    static unsigned int nprops;
    const char *names[256];
    unsigned int count = 0;

    if (!nprops) {
        PFN_enum_instance_ext enum_ext =
            (PFN_enum_instance_ext)real_gipa(NULL, "vkEnumerateInstanceExtensionProperties");
        nprops = 128;
        if (!enum_ext || enum_ext(NULL, &nprops, props) < 0)
            nprops = 0;
    }

    for (unsigned int i = 0; i < info->enabledExtensionCount && count < 128; i++)
        names[count++] = info->ppEnabledExtensionNames[i];
    for (unsigned int p = 0; p < nprops; p++) {
        unsigned int i;
        for (i = 0; i < count; i++)
            if (!strcmp(names[i], props[p].extensionName))
                break;
        if (i == count)
            names[count++] = props[p].extensionName;
    }

    app_info_t app = { STYPE_APPLICATION_INFO, NULL, NULL, 0, NULL, 0, API_1_3 };
    if (info->pApplicationInfo)
        app = *(const app_info_t *)info->pApplicationInfo;
    if (app.apiVersion < API_1_3)
        app.apiVersion = API_1_3;

    instance_info_t patched = *info;
    patched.pApplicationInfo = &app;
    patched.enabledExtensionCount = count;
    patched.ppEnabledExtensionNames = names;
    return real_create_instance(&patched, alloc, instance);
}

/* winemac resolves vkCreateMetalSurfaceEXT with dlsym() on this library (and
 * sometimes with a NULL instance), neither of which Mesa supports; route it
 * through the real instance. */
typedef int (*PFN_create_metal_surface)(void *instance, const void *info, const void *alloc, void *surface);

static int shim_create_metal_surface(void *instance, const void *info, const void *alloc, void *surface)
{
    PFN_create_metal_surface fn =
        (PFN_create_metal_surface)real_gipa(instance, "vkCreateMetalSurfaceEXT");
    return fn ? fn(instance, info, alloc, surface) : -7; /* VK_ERROR_EXTENSION_NOT_PRESENT */
}

/* Every other MoltenVK export comes through -reexport_library. */
__attribute__((visibility("default")))
int vkCreateMetalSurfaceEXT(void *instance, const void *info, const void *alloc, void *surface)
{
    pthread_once(&once, init);
    if (!real_gipa)
        return -3; /* VK_ERROR_INITIALIZATION_FAILED */
    return shim_create_metal_surface(instance, info, alloc, surface);
}

__attribute__((visibility("default")))
PFN_vkVoidFunction vkGetDeviceProcAddr(void *device, const char *name);

__attribute__((visibility("default")))
PFN_vkVoidFunction vkGetInstanceProcAddr(void *instance, const char *name)
{
    pthread_once(&once, init);
    if (!real_gipa)
        return NULL;
    if (instance)
        last_instance = instance;
    if (using_kk && !instance && !strcmp(name, "vkCreateInstance")) {
        real_create_instance = (PFN_create_instance)real_gipa(NULL, name);
        return real_create_instance ? (PFN_vkVoidFunction)shim_create_instance : NULL;
    }
    if (using_kk && !instance && !strcmp(name, "vkCreateMetalSurfaceEXT"))
        return (PFN_vkVoidFunction)shim_create_metal_surface;
    PFN_vkVoidFunction fn = wrap_props(instance, name, real_gipa(instance, name));
    if (!fn && !instance && strcmp(name, "vkGetDeviceProcAddr") == 0)
        fn = (PFN_vkVoidFunction)vkGetDeviceProcAddr;
    return fn;
}

__attribute__((visibility("default")))
PFN_vkVoidFunction vkGetDeviceProcAddr(void *device, const char *name)
{
    typedef PFN_vkVoidFunction (*PFN_gdpa)(void *, const char *);
    static PFN_gdpa gdpa;
    pthread_once(&once, init);
    if (!gdpa && real_gipa && last_instance)
        gdpa = (PFN_gdpa)real_gipa(last_instance, "vkGetDeviceProcAddr");
    return gdpa ? gdpa(device, name) : NULL;
}
