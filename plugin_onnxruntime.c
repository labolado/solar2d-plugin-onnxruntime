/**
 * plugin.onnxruntime — Solar2D native plugin for ONNX Runtime inference.
 *
 * Provides a general-purpose ONNX model loader and runner.
 * Works on macOS, iOS, Android, Windows.
 *
 * Lua API:
 *   local ort = require("plugin.onnxruntime")
 *   local session = ort.load(modelPath [, opts])
 *   local outputs = session:run({ inputName = {dims={...}, data={...}} })
 *   session:close()
 *
 * opts table (optional):
 *   ep = "coreml"    -- use CoreML EP (iOS/macOS)
 *   ep = "directml"  -- use DirectML EP (Windows)
 *   ep = "cpu"       -- default CPU EP
 *
 * Input data can be:
 *   - Lua table of numbers (original API)
 *   - Binary string of floats/int64s (set binary=true)
 *
 * Output data includes:
 *   - data = { ... }          (Lua table, always present)
 *   - data_binary = "..."     (raw float bytes, for large tensors)
 */

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#ifdef _WIN32
#include <windows.h>
#endif

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "onnxruntime_c_api.h"

/* Platform-specific EP headers */
#if defined(__APPLE__)
  #if __has_include("coreml_provider_factory.h")
    #include "coreml_provider_factory.h"
    #define HAS_COREML_EP 1
  #else
    #define HAS_COREML_EP 0
  #endif
#endif
#if defined(_WIN32)
  #include <windows.h>
  typedef OrtStatusPtr (ORT_API_CALL *PFN_OrtSessionOptionsAppendExecutionProvider_DML)(
      OrtSessionOptions* options, int device_id);
#endif

/* ── Lua 5.1 / 5.2+ compat ───────────────────────────────
 * Solar2D uses Lua 5.1. When compiled against 5.2+ headers,
 * map newer API names back to their 5.1 equivalents.
 * ─────────────────────────────────────────────────────────── */
#if LUA_VERSION_NUM >= 502
  #define lua_objlen(L,i) lua_rawlen(L,i)
#endif

/* ── Version ─────────────────────────────────────────────── */

#ifndef PLUGIN_VERSION
#define PLUGIN_VERSION "dev"
#endif

/* ── Globals ─────────────────────────────────────────────── */

static const OrtApi *g_ort = NULL;
static OrtEnv *g_env = NULL;

#define ORT_CHECK(expr)                                              \
    do {                                                             \
        OrtStatus *_s = (expr);                                      \
        if (_s) {                                                    \
            const char *msg = g_ort->GetErrorMessage(_s);            \
            lua_pushnil(L);                                          \
            lua_pushstring(L, msg);                                  \
            g_ort->ReleaseStatus(_s);                                \
            return 2;                                                \
        }                                                            \
    } while (0)

#define ORT_CHECK_VOID(expr)                                         \
    do {                                                             \
        OrtStatus *_s = (expr);                                      \
        if (_s) {                                                    \
            fprintf(stderr, "[ort] %s\n", g_ort->GetErrorMessage(_s)); \
            g_ort->ReleaseStatus(_s);                                \
        }                                                            \
    } while (0)

/* ── Session userdata ────────────────────────────────────── */

typedef struct {
    OrtSession *session;
    OrtSessionOptions *options;
    OrtAllocator *allocator;
    size_t input_count;
    size_t output_count;
    char **input_names;
    char **output_names;
} OrtSessionUD;

static const char *SESSION_MT = "OrtSession";

static OrtSessionUD *check_session(lua_State *L, int idx) {
    return (OrtSessionUD *)luaL_checkudata(L, idx, SESSION_MT);
}

/* ── Helper: read Lua table of numbers into float array ── */

static int table_to_floats(lua_State *L, int idx, float **out, size_t *count) {
    if (!lua_istable(L, idx)) return -1;
    size_t n = (size_t)lua_objlen(L, idx);
    float *buf = (float *)malloc(n * sizeof(float));
    if (!buf) return -1;
    for (size_t i = 0; i < n; i++) {
        lua_rawgeti(L, idx, (int)(i + 1));
        buf[i] = (float)lua_tonumber(L, -1);
        lua_pop(L, 1);
    }
    *out = buf;
    *count = n;
    return 0;
}

/* ── Helper: read Lua table of numbers into int64 array ── */

static int table_to_int64s(lua_State *L, int idx, int64_t **out, size_t *count) {
    if (!lua_istable(L, idx)) return -1;
    size_t n = (size_t)lua_objlen(L, idx);
    int64_t *buf = (int64_t *)malloc(n * sizeof(int64_t));
    if (!buf) return -1;
    for (size_t i = 0; i < n; i++) {
        lua_rawgeti(L, idx, (int)(i + 1));
        buf[i] = (int64_t)lua_tointeger(L, -1);
        lua_pop(L, 1);
    }
    *out = buf;
    *count = n;
    return 0;
}

/* ── Helper: read dims from Lua table ──────────────────── */

static int table_to_dims(lua_State *L, int idx, int64_t **out, size_t *ndims) {
    if (!lua_istable(L, idx)) return -1;
    size_t n = (size_t)lua_objlen(L, idx);
    int64_t *buf = (int64_t *)malloc(n * sizeof(int64_t));
    if (!buf) return -1;
    for (size_t i = 0; i < n; i++) {
        lua_rawgeti(L, idx, (int)(i + 1));
        buf[i] = (int64_t)lua_tointeger(L, -1);
        lua_pop(L, 1);
    }
    *out = buf;
    *ndims = n;
    return 0;
}

/* ── ort.load(modelPath [, opts]) → session userdata ──── */

static int ort_load(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);

    /* Lazy init */
    if (!g_ort) {
        g_ort = OrtGetApiBase()->GetApi(ORT_API_VERSION);
    }
    if (!g_env) {
        ORT_CHECK(g_ort->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "solar2d", &g_env));
    }

    OrtSessionUD *ud = (OrtSessionUD *)lua_newuserdata(L, sizeof(OrtSessionUD));
    memset(ud, 0, sizeof(OrtSessionUD));
    luaL_getmetatable(L, SESSION_MT);
    lua_setmetatable(L, -2);

    /* Session options */
    ORT_CHECK(g_ort->CreateSessionOptions(&ud->options));
    ORT_CHECK(g_ort->SetIntraOpNumThreads(ud->options, 1));
    ORT_CHECK(g_ort->SetSessionGraphOptimizationLevel(ud->options, ORT_ENABLE_ALL));

    /* Parse opts table (arg 2) */
    const char *ep_name = NULL;
    if (lua_istable(L, 2)) {
        lua_getfield(L, 2, "ep");
        if (lua_isstring(L, -1)) {
            ep_name = lua_tostring(L, -1);
        }
        lua_pop(L, 1);
    }

    /* Append execution provider */
    if (ep_name) {
#if defined(__APPLE__) && HAS_COREML_EP
        if (strcmp(ep_name, "coreml") == 0) {
            uint32_t coreml_flags = COREML_FLAG_ENABLE_ON_SUBGRAPH;
            OrtStatus *ep_s = OrtSessionOptionsAppendExecutionProvider_CoreML(ud->options, coreml_flags);
            if (ep_s) {
                fprintf(stderr, "[ort] CoreML EP failed: %s (falling back to CPU)\n",
                        g_ort->GetErrorMessage(ep_s));
                g_ort->ReleaseStatus(ep_s);
            }
        }
#endif
#if defined(_WIN32)
        if (strcmp(ep_name, "directml") == 0) {
            HMODULE ort_dll = GetModuleHandleA("onnxruntime.dll");
            if (ort_dll) {
                PFN_OrtSessionOptionsAppendExecutionProvider_DML pfn =
                    (PFN_OrtSessionOptionsAppendExecutionProvider_DML)
                    GetProcAddress(ort_dll, "OrtSessionOptionsAppendExecutionProvider_DML");
                if (pfn) {
                    OrtStatus *ep_s = pfn(ud->options, 0);
                    if (ep_s) {
                        fprintf(stderr, "[ort] DirectML EP failed: %s (falling back to CPU)\n",
                                g_ort->GetErrorMessage(ep_s));
                        g_ort->ReleaseStatus(ep_s);
                    }
                } else {
                    fprintf(stderr, "[ort] DirectML EP not available in this ORT build\n");
                }
            }
        }
#endif
    }

    /* Create session — Windows requires wchar_t path */
#ifdef _WIN32
    {
        int wlen = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
        wchar_t *wpath = (wchar_t *)malloc(wlen * sizeof(wchar_t));
        MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, wlen);
        ORT_CHECK(g_ort->CreateSession(g_env, wpath, ud->options, &ud->session));
        free(wpath);
    }
#else
    ORT_CHECK(g_ort->CreateSession(g_env, path, ud->options, &ud->session));
#endif

    /* Get default allocator */
    ORT_CHECK(g_ort->GetAllocatorWithDefaultOptions(&ud->allocator));

    /* Query input names */
    ORT_CHECK(g_ort->SessionGetInputCount(ud->session, &ud->input_count));
    ud->input_names = (char **)calloc(ud->input_count, sizeof(char *));
    for (size_t i = 0; i < ud->input_count; i++) {
        char *name = NULL;
        ORT_CHECK(g_ort->SessionGetInputName(ud->session, i, ud->allocator, &name));
        ud->input_names[i] = strdup(name);
        ORT_CHECK_VOID(g_ort->AllocatorFree(ud->allocator, name));
    }

    /* Query output names */
    ORT_CHECK(g_ort->SessionGetOutputCount(ud->session, &ud->output_count));
    ud->output_names = (char **)calloc(ud->output_count, sizeof(char *));
    for (size_t i = 0; i < ud->output_count; i++) {
        char *name = NULL;
        ORT_CHECK(g_ort->SessionGetOutputName(ud->session, i, ud->allocator, &name));
        ud->output_names[i] = strdup(name);
        ORT_CHECK_VOID(g_ort->AllocatorFree(ud->allocator, name));
    }

    return 1; /* return session userdata */
}

/* ── session:run(inputs) → outputs table ─────────────── */

static int session_run(lua_State *L) {
    OrtSessionUD *ud = check_session(L, 1);
    if (!ud->session) {
        return luaL_error(L, "session already closed");
    }
    luaL_checktype(L, 2, LUA_TTABLE);

    OrtMemoryInfo *mem_info = NULL;
    ORT_CHECK(g_ort->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &mem_info));

    /* Build input tensors */
    size_t n_in = ud->input_count;
    const char **in_names = (const char **)ud->input_names;
    OrtValue **in_values = (OrtValue **)calloc(n_in, sizeof(OrtValue *));
    void **in_bufs = (void **)calloc(n_in, sizeof(void *)); /* track for cleanup */
    int *in_buf_owned = (int *)calloc(n_in, sizeof(int)); /* whether we need to free */

    for (size_t i = 0; i < n_in; i++) {
        lua_getfield(L, 2, ud->input_names[i]);
        if (lua_isnil(L, -1)) {
            /* Free already-created tensors */
            for (size_t j = 0; j < i; j++) {
                g_ort->ReleaseValue(in_values[j]);
                if (in_buf_owned[j]) free(in_bufs[j]);
            }
            free(in_values); free(in_bufs); free(in_buf_owned);
            g_ort->ReleaseMemoryInfo(mem_info);
            return luaL_error(L, "missing input: %s", ud->input_names[i]);
        }

        /* Read dims */
        lua_getfield(L, -1, "dims");
        int64_t *dims = NULL;
        size_t ndims = 0;
        table_to_dims(L, -1, &dims, &ndims);
        lua_pop(L, 1);

        /* Check dtype - default to float */
        ONNXTensorElementDataType dtype = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
        lua_getfield(L, -1, "dtype");
        if (lua_isstring(L, -1)) {
            const char *dtype_str = lua_tostring(L, -1);
            if (strcmp(dtype_str, "int64") == 0) {
                dtype = ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64;
            }
        }
        lua_pop(L, 1);

        /* Check if binary mode */
        int is_binary = 0;
        lua_getfield(L, -1, "binary");
        if (lua_toboolean(L, -1)) is_binary = 1;
        lua_pop(L, 1);

        /* Read data */
        void *data = NULL;
        size_t count = 0;
        size_t elem_size = (dtype == ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64) ? sizeof(int64_t) : sizeof(float);

        lua_getfield(L, -1, "data");

        if (is_binary && lua_isstring(L, -1)) {
            /* Binary string path — zero-copy, no per-element Lua calls */
            size_t str_len = 0;
            const char *str_data = lua_tolstring(L, -1, &str_len);
            count = str_len / elem_size;
            /* Must copy because Lua may GC the string */
            data = malloc(str_len);
            memcpy(data, str_data, str_len);
            in_buf_owned[i] = 1;
        } else if (dtype == ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64) {
            int64_t *int64_data = NULL;
            table_to_int64s(L, -1, &int64_data, &count);
            data = int64_data;
            in_buf_owned[i] = 1;
        } else {
            float *float_data = NULL;
            table_to_floats(L, -1, &float_data, &count);
            data = float_data;
            in_buf_owned[i] = 1;
        }
        lua_pop(L, 1);

        in_bufs[i] = data;

        /* Create tensor */
        OrtStatus *s = g_ort->CreateTensorWithDataAsOrtValue(
            mem_info, data, count * elem_size,
            dims, ndims, dtype,
            &in_values[i]);

        free(dims);
        lua_pop(L, 1); /* pop the input table */

        if (s) {
            const char *msg = g_ort->GetErrorMessage(s);
            for (size_t j = 0; j <= i; j++) {
                if (in_values[j]) g_ort->ReleaseValue(in_values[j]);
                if (in_buf_owned[j]) free(in_bufs[j]);
            }
            free(in_values); free(in_bufs); free(in_buf_owned);
            g_ort->ReleaseMemoryInfo(mem_info);
            lua_pushnil(L);
            lua_pushstring(L, msg);
            g_ort->ReleaseStatus(s);
            return 2;
        }
    }

    /* Run */
    size_t n_out = ud->output_count;
    const char **out_names = (const char **)ud->output_names;
    OrtValue **out_values = (OrtValue **)calloc(n_out, sizeof(OrtValue *));

    OrtStatus *run_status = g_ort->Run(
        ud->session, NULL,
        in_names, (const OrtValue *const *)in_values, n_in,
        out_names, n_out, out_values);

    /* Cleanup inputs */
    for (size_t i = 0; i < n_in; i++) {
        g_ort->ReleaseValue(in_values[i]);
        if (in_buf_owned[i]) free(in_bufs[i]);
    }
    free(in_values);
    free(in_bufs);
    free(in_buf_owned);
    g_ort->ReleaseMemoryInfo(mem_info);

    if (run_status) {
        const char *msg = g_ort->GetErrorMessage(run_status);
        free(out_values);
        lua_pushnil(L);
        lua_pushstring(L, msg);
        g_ort->ReleaseStatus(run_status);
        return 2;
    }

    /* Build output table */
    lua_newtable(L);

    for (size_t i = 0; i < n_out; i++) {
        /* Get shape */
        OrtTensorTypeAndShapeInfo *info = NULL;
        g_ort->GetTensorTypeAndShape(out_values[i], &info);

        size_t out_ndims = 0;
        g_ort->GetDimensionsCount(info, &out_ndims);

        int64_t *out_dims = (int64_t *)malloc(out_ndims * sizeof(int64_t));
        g_ort->GetDimensions(info, out_dims, out_ndims);

        size_t elem_count = 1;
        for (size_t d = 0; d < out_ndims; d++) elem_count *= (size_t)out_dims[d];

        g_ort->ReleaseTensorTypeAndShapeInfo(info);

        /* Get data pointer */
        float *out_data = NULL;
        g_ort->GetTensorMutableData(out_values[i], (void **)&out_data);

        /* Create output entry: { dims={...}, data={...}, data_binary="..." } */
        lua_pushstring(L, ud->output_names[i]);
        lua_newtable(L);

        /* dims */
        lua_pushstring(L, "dims");
        lua_newtable(L);
        for (size_t d = 0; d < out_ndims; d++) {
            lua_pushinteger(L, (lua_Integer)out_dims[d]);
            lua_rawseti(L, -2, (int)(d + 1));
        }
        lua_settable(L, -3);

        /* data (Lua table — always provided for compatibility) */
        lua_pushstring(L, "data");
        lua_newtable(L);
        for (size_t e = 0; e < elem_count; e++) {
            lua_pushnumber(L, (lua_Number)out_data[e]);
            lua_rawseti(L, -2, (int)(e + 1));
        }
        lua_settable(L, -3);

        /* data_binary (raw float bytes — fast path for large tensors) */
        lua_pushstring(L, "data_binary");
        lua_pushlstring(L, (const char *)out_data, elem_count * sizeof(float));
        lua_settable(L, -3);

        lua_settable(L, -3); /* outputs[name] = {dims, data, data_binary} */

        free(out_dims);
        g_ort->ReleaseValue(out_values[i]);
    }

    free(out_values);
    return 1; /* return outputs table */
}

/* ── session:close() ─────────────────────────────────── */

static int session_close(lua_State *L) {
    OrtSessionUD *ud = check_session(L, 1);
    if (ud->session) {
        g_ort->ReleaseSession(ud->session);
        ud->session = NULL;
    }
    if (ud->options) {
        g_ort->ReleaseSessionOptions(ud->options);
        ud->options = NULL;
    }
    if (ud->input_names) {
        for (size_t i = 0; i < ud->input_count; i++) free(ud->input_names[i]);
        free(ud->input_names);
        ud->input_names = NULL;
    }
    if (ud->output_names) {
        for (size_t i = 0; i < ud->output_count; i++) free(ud->output_names[i]);
        free(ud->output_names);
        ud->output_names = NULL;
    }
    return 0;
}

/* ── session:info() → {inputs={...}, outputs={...}} ── */

static int session_info(lua_State *L) {
    OrtSessionUD *ud = check_session(L, 1);
    if (!ud->session) return luaL_error(L, "session already closed");

    lua_newtable(L);

    /* inputs */
    lua_pushstring(L, "inputs");
    lua_newtable(L);
    for (size_t i = 0; i < ud->input_count; i++) {
        lua_pushstring(L, ud->input_names[i]);
        lua_rawseti(L, -2, (int)(i + 1));
    }
    lua_settable(L, -3);

    /* outputs */
    lua_pushstring(L, "outputs");
    lua_newtable(L);
    for (size_t i = 0; i < ud->output_count; i++) {
        lua_pushstring(L, ud->output_names[i]);
        lua_rawseti(L, -2, (int)(i + 1));
    }
    lua_settable(L, -3);

    return 1;
}

/* ── session:__gc ────────────────────────────────────── */

static int session_gc(lua_State *L) {
    return session_close(L);
}

/* ── session:__tostring ──────────────────────────────── */

static int session_tostring(lua_State *L) {
    OrtSessionUD *ud = check_session(L, 1);
    lua_pushfstring(L, "OrtSession(%d inputs, %d outputs)",
        (int)ud->input_count, (int)ud->output_count);
    return 1;
}

/* ── Module registration ─────────────────────────────── */

static const luaL_Reg kSessionMethods[] = {
    { "run",       session_run },
    { "close",     session_close },
    { "info",      session_info },
    { "__gc",      session_gc },
    { "__tostring", session_tostring },
    { NULL, NULL }
};

static int ort_version(lua_State *L) {
    lua_pushstring(L, PLUGIN_VERSION);
    return 1;
}

static const luaL_Reg kModuleFunctions[] = {
    { "load", ort_load },
    { "version", ort_version },
    { NULL, NULL }
};

/* Solar2D plugin entry point */
#ifdef _WIN32
__declspec(dllexport)
#endif
int luaopen_plugin_onnxruntime(lua_State *L) {
    /* Create session metatable */
    luaL_newmetatable(L, SESSION_MT);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    luaL_register(L, NULL, kSessionMethods);
    lua_pop(L, 1);

    /* Register module functions */
    luaL_register(L, "plugin.onnxruntime", kModuleFunctions);

    /* ort.VERSION */
    lua_pushstring(L, PLUGIN_VERSION);
    lua_setfield(L, -2, "VERSION");

    return 1;
}
