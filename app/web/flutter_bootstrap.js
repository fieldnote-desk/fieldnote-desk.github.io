{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: { canvasKitBaseUrl: 'canvaskit/' },
  onEntrypointLoaded: async engineInitializer => {
    try {
      const runner = await engineInitializer.initializeEngine();
      await runner.runApp();
    } catch {
      window.fieldnoteLoadError();
    }
  },
}).catch(window.fieldnoteLoadError);
