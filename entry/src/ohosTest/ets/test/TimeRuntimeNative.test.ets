import { describe, it, expect } from '@ohos/hypium';
import { i18n } from '@kit.LocalizationKit';
import { DeadlineTime } from '../../../main/ets/services/DeadlineTime';
import { LocalizationService } from '../../../main/ets/services/LocalizationService';

export default function timeRuntimeNativeTest() {
  describe('timeRuntimeNative', () => {
    it('reports only non-sensitive runtime calendar and formatting diagnostics',0,() => {
      const instant=Date.parse('2026-10-06T03:59:00Z');
      const date=new Date(instant);const zone=i18n.getTimeZone().getID();
      const implicit=new Intl.DateTimeFormat('en-US',{hour:'numeric',minute:'2-digit',hour12:false}).format(date);
      const explicit=new Intl.DateTimeFormat('en-US',{hour:'numeric',minute:'2-digit',hour12:false,timeZone:zone}).format(date);
      console.info('DAYLINE_TIME_RUNTIME '+JSON.stringify({zone,localTime:DeadlineTime.timeKey(instant),offset:date.getTimezoneOffset(),implicit,explicit,app:LocalizationService.formatDateTime(date)}));
      expect(Number.isFinite(instant)).assertTrue();
    });
    it('formats with the real system zone rather than an implicit ICU default',0,() => {
      const date=new Date(Date.parse('2026-10-06T03:59:00Z'));
      const explicit=new Intl.DateTimeFormat(LocalizationService.getEffectiveLocale(),{
        dateStyle:'medium',timeStyle:'short',hour12:!LocalizationService.uses24HourClock(),timeZone:i18n.getTimeZone().getID()
      }).format(date);
      expect(LocalizationService.formatDateTime(date)).assertEqual(explicit);
    });
  });
}
