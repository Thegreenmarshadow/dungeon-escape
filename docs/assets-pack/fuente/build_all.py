"""Genera todo el paquete en out/ desde cero (requiere Python 3 + Pillow)."""
import runpy
import export, weapon_export, weapon2_export, boss_export, props_export, sheet

export.main()            # borra out/ y crea enemigos + proyectiles
weapon_export.main()     # 6 armas base
weapon2_export.main()    # 15 armas nuevas (+ weapon_data.gd ampliado)
boss_export.main()       # 3 jefes + efectos (+ GIF)
props_export.main()      # objetos de los 3 temas + herramienta de recoloreo
runpy.run_path('gifs.py')   # GIF de enemigos
runpy.run_path('wgif.py')   # GIF de las 6 armas base
sheet.main(['out/docs/vista_previa/hoja_general.png'])
print('listo')
