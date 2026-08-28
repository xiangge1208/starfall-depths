# FNV-1a-64 参考实现（与 autoload/rng_svc.gd 的 RngSvc.stable_hash 逐位一致的 Python 版）。
# 用途：为 tests/unit/test_rng.gd 的 test_stable_hash_known_vector 提供跨实现字面量锚点——
# 若 GDScript 侧哈希被重构或引擎升级改变位型，测试将对照这里的输出立即失败。
#
# 算法（与 GDScript 相同）：
#   basis = 0xcbf29ce484222325, prime = 0x100000001b3, 掩码取 64 位
#   对 [a, b] 各做 8 轮小端字节迭代：h ^= x & 0xFF; h = h * prime mod 2^64; x >>= 8
# 输入按 int64 二补码解释（负数同样成立：Python 的 & 0xFF / >> 与算术移位语义一致），
# 返回值转为带符号 int64（与 GDScript 返回域一致，便于直接写进测试的十进制字面量）。
#
# 运行：python tests/unit/fnv_reference.py
# 注意：期望值必须用十进制——Godot 4.7.2 会把超出 int64 正域的十六进制字面量钳到 INT64_MAX。

MASK = (1 << 64) - 1
BASIS = 0xCBF29CE484222325
PRIME = 0x100000001B3


def _to_signed64(v: int) -> int:
    return v - (1 << 64) if v >= (1 << 63) else v


def stable_hash(a: int, b: int) -> int:
    h = BASIS
    for v in (a, b):
        x = v
        for _ in range(8):
            h ^= x & 0xFF
            h = (h * PRIME) & MASK
            x >>= 8
    return _to_signed64(h)


if __name__ == "__main__":
    for a, b in [(0, 0), (1, 2), (2, 1)]:
        v = stable_hash(a, b)
        print("stable_hash(%d, %d) = %d  (hex bit pattern: 0x%016x)" % (a, b, v, v & MASK))
