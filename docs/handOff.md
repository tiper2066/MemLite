# MemLite 인수인계

다음 세션은 이 파일의 체크박스를 위에서부터 구현한다. 사양의 기준 문서는 [development-plan.md](development-plan.md)이다. 끝난 항목은 `- [x]`로 바꾼다. 앱 이름은 **MemLite**이다.

## 현재 상태

- 9단계와 이후 아이콘·로그인·버전·메뉴 정크 용량 확인까지 마쳤다. 설치 위치는 `/Applications/MemLite.app`이고, 설치 파일은 `dist/MemLite.dmg`이다.
- 저장소는 [https://github.com/tiper2066/MemLite](https://github.com/tiper2066/MemLite)이다.
- 작성된 문서는 `README.md`, `docs/development-plan.md`, `docs/handOff.md`이다.
- 개인용 macOS 메뉴 막대 앱이다. 최소 버전은 macOS 14.0 (Sonoma)이다.
- 앱 아이콘은 `assets/icon-menubar.png`이다. 메뉴 막대에는 아이콘을 넣지 않는다.

## 구현할 때 지킬 것

- UI는 AppKit `NSStatusItem`이다. SwiftUI `MenuBarExtra`는 쓰지 않는다. 메뉴 막대에서 글자색이 빠진다.
- `LSUIElement`로 Dock 아이콘과 메인 창을 없앤다.
- App Sandbox는 끈다. App Store 제출과 공증은 하지 않는다.
- 메모리 색은 사용 비율이 아니라 `kern.memorystatus_vm_pressure_level`을 따른다.
- 메모리 정리(파일 캐시 강제 비우기)는 넣지 않는다.
- 정크 용량은 메뉴를 열 때만 읽고, 삭제는 **정크 파일 정리…** 를 골랐을 때만 한다. 2초 갱신에는 넣지 않는다.
- 지우면 계정, 동기화, 보관함, 보안, 시스템 동작에 문제가 되는 파일은 용량 계산과 삭제 모두에서 뺀다.
- 메뉴 막대에는 이미지를 넣지 않는다. 앱 아이콘만 Finder에 쓴다.
- 로그인 시 열기는 설정 창 없이 `SMAppService.mainApp`만 쓴다.

## 1. Xcode 프로젝트

- [x] macOS App 타깃 이름과 제품 이름을 `MemLite`로 만든다.
- [x] 배포 타깃을 macOS 14.0으로 둔다.
- [x] Swift와 AppKit을 사용한다.
- [x] App Sandbox를 끈다.
- [x] `Info.plist`에 `LSUIElement` = `YES`를 넣는다.
- [x] 아래 파일을 둔다.
  - `MemLite/MemLiteApp.swift`
  - `MemLite/AppDelegate.swift`
  - `MemLite/MemorySnapshot.swift`
  - `MemLite/MemoryReader.swift`
  - `MemLite/JunkCleaner.swift`
  - `MemLite/StatusItemController.swift`
- [x] 진입점에서 `AppDelegate`를 연결하고, 시작 시 메인 창을 만들지 않는다.

## 2. 메모리 스냅샷

- [x] `MemorySnapshot`에 바이트 값으로 물리적 메모리, 사용된 메모리, 캐시된 파일, 스왑, 앱 메모리, 와이어드 메모리, 압축됨을 둔다.
- [x] 압력 단계는 `normal`(0x1), `warning`(0x2), `urgent`(0x4), `critical`(0x8)로 구분한다. `urgent`와 `critical`은 위험으로 묶는다.
- [x] `MemoryReader`가 `sysctl` `hw.memsize`로 물리적 메모리를 읽는다.
- [x] `host_statistics64`의 `vm_statistics64`로 페이지 수를 읽고, 페이지 크기를 곱해 바이트로 환산한다.
- [x] 앱 메모리 = `(internal_page_count - purgeable_count) * pageSize`
- [x] 와이어드 메모리 = `wire_count * pageSize`
- [x] 압축됨 = `compressor_page_count * pageSize`
- [x] 캐시된 파일 = `(external_page_count + purgeable_count) * pageSize`
- [x] 사용된 메모리 = 앱 메모리 + 와이어드 메모리 + 압축됨
- [x] 스왑은 `sysctl` `vm.swapusage`의 `xsu_used`를 읽는다.
- [x] 압력은 `sysctl` `kern.memorystatus_vm_pressure_level`을 읽는다.
- [x] 관리자 권한이나 개인정보 접근 권한 요청은 넣지 않는다.
- [x] 반올림은 표시 직전에만 한다. 스냅샷에는 바이트를 유지한다.

## 3. 표시 문자열

- [x] 메뉴 막대 형식은 `19.7 / 24 GB`이다. GB 소수 한 자리, 단위는 끝에 한 번만 붙인다.
- [x] 상세 메뉴는 GB 소수 두 자리이며 `24.00GB`처럼 숫자와 단위를 붙인다.
- [x] 스왑이 0이면 `0바이트`로 표시한다. 0보다 크면 다른 상세 항목과 같이 GB 소수 두 자리다.
- [x] 상세 항목 이름은 활성상태보기와 같다. 물리적 메모리, 사용된 메모리, 캐시된 파일, 사용된 스왑 공간, 앱 메모리, 와이어드 메모리, 압축됨.

## 4. 메뉴 막대 문구와 색

- [x] `NSStatusItem`의 `attributedTitle`로 문구를 그린다.
- [x] 사용량 숫자만 압력 색을 칠한다. 안전은 녹색, 주의는 주황색, 위험은 빨간색이다.
- [x] `/ 24 GB`는 메뉴 막대 기본 글자색으로 둔다.
- [x] 메뉴가 열려 항목이 강조된 동안에는 사용량 숫자도 기본 글자색으로 되돌린다.
- [x] 메뉴가 닫히면 압력 색을 다시 칠한다.
- [x] 동그라미나 네모 아이콘은 넣지 않는다.
- [x] 압력 단계와 표시 문자열이 그대로면 문구를 다시 그리지 않는다.

## 5. 클릭 메뉴

- [x] 왼쪽 메모리 압력 그래프는 넣지 않는다.
- [x] 상세 7항목을 메뉴에 표시한다. 이 항목은 눌리지 않는 정보 행이다.
- [x] 상세 항목 아래 구분선을 둔다.
- [x] 눌리지 않는 정크 용량 4항목을 둔다. 휴지통, 사용자 캐시, 사용자 로그, 정크 합계.
- [x] 메뉴를 열면 정크 용량을 읽고, 끝나기 전에는 `계산 중…`을 보여 준다.
- [x] **정크 파일 정리…** 항목을 둔다.
- [x] **로그인 시 열기** 항목을 두고, `SMAppService.mainApp`으로 켜고 끈다.
- [x] 그 아래 구분선을 둔다.
- [x] 눌리지 않는 **MemLite 1.0** 버전 한 줄을 둔다.
- [x] **종료** 항목을 두고, 선택하면 앱을 종료한다.
- [x] 메뉴가 열린 동안 메모리 수치를 갱신한다. 색은 4번의 강조 규칙을 따른다.

## 6. 2초 갱신

- [x] `AppDelegate`가 약 2초마다 `MemoryReader`만 호출한다.
- [x] 한 주기에 `host_statistics64` 한 번과 필요한 `sysctl`만 호출한다.
- [x] 정크 파일 용량 계산과 삭제는 이 타이머에 넣지 않는다.
- [x] 메뉴가 열려 있는지 `StatusItemController`에 전달한다.

## 7. 정크 파일 정리

- [x] 대기 중과 2초 타이머에는 `~/.Trash`, `~/Library/Caches`, `~/Library/Logs`를 순회하지 않는다.
- [x] 메뉴를 열 때 세 위치의 용량을 읽어 메뉴에 보여 준다.
- [x] **정크 파일 정리…** 는 지우기 확인에만 쓴다. 방금 읽은 용량이 있으면 다시 스캔하지 않는다.
- [x] 용량 계산과 삭제는 메인 스레드 밖에서 한다. 그동안 메뉴 막대 메모리 표시는 계속 갱신한다.
- [x] 확인 창은 지우기 직전에만 뜨는 알림으로 둔다. 상주 창으로 만들지 않는다.
- [x] 확인 창에는 지워도 되는 용량만 휴지통, 사용자 캐시, 사용자 로그, 합계로 보여 준다.
- [x] 취소를 누르면 아무 파일도 지우지 않는다.
- [x] 확인하면 지워도 되는 파일만 지운다. 세 폴더 자체는 남긴다.
- [x] 끝난 뒤 실제로 지운 용량을 짧게 알린다.
- [x] 공통으로 뺀다. 세 폴더 자체, 폴더 밖을 가리키는 심볼릭 링크와 앨리어스, 링크의 원본, 잠긴 파일(`UF_IMMUTABLE`, `SF_IMMUTABLE`, `UF_APPEND`), 다른 프로세스가 연 파일, 경로를 풀었을 때 세 위치 밖에 있는 파일.
- [x] 휴지통은 사용자가 이미 버린 파일만 지운다. `/Library`, `/System`, 외장 볼륨 휴지통은 넣지 않는다.
- [x] 로그는 일반 로그와 진단 리포트만 지운다.
- [x] `~/Library/Caches` 바로 아래 이름이 다음이면 그 폴더 전체를 용량과 삭제에서 뺀다.
  - 계정·보안: `com.apple.akd`, `com.apple.accountsd`, `com.apple.AppleMediaServices`, `com.apple.amsaccountsd`, `com.apple.amsengagementd`, `com.apple.identityservicesd`, `com.apple.ids`, `com.apple.security`, `com.apple.ProtectedCloudStorage`, `com.apple.TrustEvaluationAgent`
  - iCloud·동기화: `CloudKit`, `com.apple.bird`, `com.apple.CloudDocs`, `com.apple.iCloudDriveCore`, `com.apple.HomeKit`, `com.apple.icloud`로 시작하는 항목
  - 메일·메시지·사진·음악: `com.apple.Mail`, `com.apple.mail`, `com.apple.Messages`, `com.apple.imfoundation`, `com.apple.imagent`, `com.apple.Photos`, `com.apple.photolibraryd`, `com.apple.Music`, `com.apple.iTunes`, `com.apple.itunescloudd`, `com.apple.AMPLibraryAgent`
  - 시스템 동작: `com.apple.Spotlight`, `com.apple.FontRegistry`, `com.apple.ATS`, `com.apple.nsurlsessiond`, `com.apple.nsurlstoraged`, `com.apple.MobileAsset`로 시작하는 항목, `com.apple.sharedfilelist`, `com.apple.containermanagerd`
- [x] 디스크 전체 검색, 브라우저 프로필 정리, 개발 도구 찌꺼기 정리, 메모리 정리는 넣지 않는다.

## 8. 설치용 DMG

- [x] 앞 단계의 동작 확인이 끝난 뒤 Release로 `MemLite.app`을 빌드한다.
- [x] `scripts/create-dmg.sh`를 만들어 `dist/MemLite.dmg`를 생성한다.
- [x] DMG 안에는 `MemLite.app`과 `/Applications`로 연결되는 응용 프로그램 폴더 링크만 둔다.
- [x] 디스크를 열면 창 제목이 `MemLite`이고, 앱과 응용 프로그램 폴더가 나란히 보여 끌어다 놓으면 설치되게 한다.
- [x] 공증과 App Store 업로드는 하지 않는다.

## 9. 확인

로컬에서 실행한 뒤 활성상태보기 메모리 탭과 비교한다.

- [x] Dock 아이콘과 메인 창이 없다.
- [x] 메뉴 막대 문구가 `사용량 / 전체 GB` 형식이다.
- [x] 사용량 숫자만 녹색, 주황색, 빨간색 중 하나이고 나머지 글자는 기본색이다.
- [x] 메뉴를 연 동안 사용량 숫자가 기본 글자색으로 바뀌고, 닫으면 압력 색이 돌아온다.
- [x] 상세 7항목이 활성상태보기와 같은 기준이다. GB 반올림 차이만 허용한다.
- [x] 스왑이 없으면 `0바이트`로 보인다.
- [x] 메뉴를 열면 휴지통, 사용자 캐시, 사용자 로그, 정크 합계가 보인다.
- [x] 정크 용량 읽기는 2초 타이머에 넣지 않는다.
- [x] 정리를 고르기 전에는 파일을 지우지 않는다. 확인 창에서 취소하면 파일이 지워지지 않는다.
- [x] 확인하면 그 파일만 지워지고 세 폴더 자체는 남는다.
- [x] 제외 목록의 캐시, 잠긴 파일, 사용 중인 파일, 폴더 밖 링크는 용량에 없고 지워지지도 않는다.
- [x] 종료를 누르면 메뉴 막대에서 사라진다.
- [x] `dist/MemLite.dmg`를 열면 앱과 응용 프로그램 폴더가 보인다.
- [x] 앱을 응용 프로그램 폴더로 복사하면 `/Applications/MemLite.app`에 설치된다.
- [x] 설치한 MemLite를 한 번 열면 메뉴 막대에 나타난다.

## 10. 아이콘, 로그인, 버전

- [x] 응용 프로그램 폴더 앱 아이콘은 `assets/icon-menubar.png`로 둔다. 작은 크기에서 뭉개지는 `assets/icon-app.png`는 쓰지 않는다.
- [x] 메뉴 막대에는 아이콘을 넣지 않고 숫자만 그린다.
- [x] 메뉴에 **로그인 시 열기**를 둔다. 응용 프로그램 폴더에 설치한 앱에서만 등록한다. 실패하면 안내를 띄운다.
- [x] 메뉴에 눌리지 않는 **MemLite 1.0**을 둔다.
- [x] `README.md`에 클론과 `./scripts/create-dmg.sh`로 설치 파일을 만드는 방법을 둔다.

## 11. 메뉴 정크 용량

- [x] 메뉴를 열면 휴지통, 사용자 캐시, 사용자 로그, 정크 합계를 눌리지 않는 행으로 보여 준다.
- [x] 읽기는 메뉴를 열 때만 하고, 2초 메모리 갱신에는 넣지 않는다.
- [x] 값이 오기 전에는 `계산 중…`을 보여 준다.
- [x] **정크 파일 정리…** 는 지우기 확인용으로 남긴다.
