# ONNX Runtime WASM - HTML5 测试

## 测试文件说明

### test-ort.html
基础的 ONNX Runtime Web 功能测试页面，验证：
- WASM 模块加载
- 简单推理（Add 操作）
- Tensor 操作

### ort-integration.html
完整的集成测试页面，包含：
- 环境检测（WASM、SIMD 支持）
- ORT 初始化
- 自动测试套件
- 性能指标显示

## 使用方法

1. 启动本地服务器：
```bash
cd web/test-html5
python3 -m http.server 8765
```

2. 浏览器访问：
- http://localhost:8765/test-ort.html
- http://localhost:8765/ort-integration.html

3. 按页面按钮运行测试

## 预期结果

所有测试应显示 ✅：
- Environment check - pass
- ORT initialization - pass  
- Simple inference - pass
- Tensor operations - pass

## 集成到 Solar2D

Solar2D HTML5 构建产物需要使用 `plugin_js` API 来加载 WASM 模块。
参见 `web/dist/onnxruntime.lua` 的示例实现。
