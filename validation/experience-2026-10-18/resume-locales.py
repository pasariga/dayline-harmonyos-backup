from pathlib import Path
text=Path(__file__).with_name('runtime-locales.py').read_text(encoding='utf-8')
prefix=text[:text.index("change('zh_CN'")]
exec(compile(prefix,'locale-definitions','exec'))
o['system_tap'](values('en_US')['editor_discard_action'])
suffix=text[text.index("change('en_US','de_DE'"):]
exec(compile(suffix,'locale-resume','exec'))
