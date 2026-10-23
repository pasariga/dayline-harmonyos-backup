from pathlib import Path
import json
texts={
'base':['这个时间已过去，请选择未来的截止时间。输入内容已保留。','这一天没有所选时间，请选择另一个时间。','这一天所选时间会出现两次，请选择不重复的时间。'],
'zh_CN':['这个时间已过去，请选择未来的截止时间。输入内容已保留。','这一天没有所选时间，请选择另一个时间。','这一天所选时间会出现两次，请选择不重复的时间。'],
'zh_TW':['這個時間已過，請選擇未來的截止時間。輸入內容已保留。','這一天沒有所選時間，請選擇另一個時間。','這一天所選時間會出現兩次，請選擇不重複的時間。'],
'en_US':['This time has passed. Choose a future deadline; your entries are kept.','This time does not exist on that date. Choose another time.','This time occurs twice on that date. Choose a time that is not repeated.'],
'de_DE':['Dieser Zeitpunkt liegt in der Vergangenheit. Wähle einen zukünftigen Termin. Deine Eingaben bleiben erhalten.','Diese Uhrzeit gibt es an diesem Datum nicht. Wähle eine andere Uhrzeit.','Diese Uhrzeit kommt an diesem Datum zweimal vor. Wähle eine eindeutige Uhrzeit.'],
'fr_FR':['Cette heure est passée. Choisis une échéance future ; tes saisies sont conservées.','Cette heure n’existe pas à cette date. Choisis une autre heure.','Cette heure se répète à cette date. Choisis une heure sans ambiguïté.'],
'es_ES':['Esta hora ya pasó. Elige una fecha futura; se conservan tus datos.','Esta hora no existe en esa fecha. Elige otra hora.','Esta hora se repite en esa fecha. Elige una hora que no se repita.'],
'ja_JP':['この時刻は過ぎています。未来の期限を選んでください。入力内容は保持されています。','この日には選択した時刻が存在しません。別の時刻を選んでください。','この日は選択した時刻が2回あります。重複しない時刻を選んでください。'],
'ko_KR':['이미 지난 시간입니다. 앞으로의 마감 시간을 선택하세요. 입력 내용은 유지됩니다.','이 날짜에는 선택한 시간이 없습니다. 다른 시간을 선택하세요.','이 날짜에는 선택한 시간이 두 번 나타납니다. 중복되지 않는 시간을 선택하세요.']}
keys=['validation_time_past','validation_time_missing','validation_time_ambiguous']
for locale,values in texts.items():
    p=Path('entry/src/main/resources')/locale/'element/messages.json'
    raw=json.loads(p.read_text(encoding='utf-8'))
    for key,value in zip(keys,values):
        if not any(item['name']==key for item in raw['string']):raw['string'].append({'name':key,'value':value})
    p.write_text(json.dumps(raw,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Nine locales; three date validation messages')
