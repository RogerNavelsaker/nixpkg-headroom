import importlib.util

from headroom.compression.detector import FallbackDetector, get_detector
from headroom.cli.proxy import ensure_proxy_dependencies


def test_magika_is_absent_and_detector_uses_fallback() -> None:
    assert importlib.util.find_spec("magika") is None
    assert isinstance(get_detector(), FallbackDetector)


def test_proxy_dependency_check_allows_missing_magika() -> None:
    ensure_proxy_dependencies()
