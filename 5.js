// src/directives/lazy.js

export default {
  mounted(el, binding) {
    // SSR 保护
    if (typeof window === 'undefined') return

    // 解析参数
    const opts = typeof binding.value === 'string'
      ? { src: binding.value }
      : binding.value || {}

    const { src, loading, error, background } = opts

    // 设置 loading 占位
    if (loading) {
      if (background) {
        el.style.backgroundImage = `url(${loading})`
      } else {
        el.src = loading
      }
    }

    // 创建 observer（单例）
    if (!window.__lazyObserver) {
      window.__lazyObserver = new IntersectionObserver(entries => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            const target = entry.target
            const { _lazySrc, _lazyError, _lazyBackground } = target

            const img = new Image()
            img.src = _lazySrc

            img.onload = () => {
              if (_lazyBackground) {
                target.style.backgroundImage = `url(${_lazySrc})`
              } else {
                target.src = _lazySrc
              }
            }

            img.onerror = () => {
              if (_lazyError) {
                if (_lazyBackground) {
                  target.style.backgroundImage = `url(${_lazyError})`
                } else {
                  target.src = _lazyError
                }
              }
            }

            window.__lazyObserver.unobserve(target)
          }
        })
      })
    }

    // 把数据挂到元素上
    el._lazySrc = src
    el._lazyError = error
    el._lazyBackground = background

    // 开始监听
    window.__lazyObserver.observe(el)
  },

  unmounted(el) {
    window.__lazyObserver && window.__lazyObserver.unobserve(el)
  }
}
