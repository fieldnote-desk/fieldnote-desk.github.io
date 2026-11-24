{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: { canvasKitBaseUrl: 'canvaskit/' },
  onEntrypointLoaded: async engineInitializer => {
    try {
      const runner = await engineInitializer.initializeEngine();
      await runner.runApp();
      document.getElementById('loading')?.remove();
    } catch {
      const loader = document.getElementById('loading');
      if (loader?.firstElementChild) loader.firstElementChild.textContent = '简报台暂时无法打开';
    }
  },
});
