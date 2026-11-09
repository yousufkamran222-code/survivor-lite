extends Node
## Real ads on Android through the Poing Studios AdMob plugin (addons/admob,
## v5.1.0). Only `Ads` (ad_service.gd) creates this, and only when the
## plugin's native singleton exists, so web, desktop and tests never load it.
##
## Startup: the UMP consent check (and its form, for EEA/UK users), then the
## Mobile Ads SDK, then one rewarded and one interstitial ad are loaded and
## kept ready; each is reloaded after it's shown, failed loads retry with a
## growing delay.
##
## Ad unit IDs are Google's TEST IDs unless the store build injects real ones
## into project settings (petri/admob/*, from CI secrets: never commit them).

const TEST_REWARDED := "ca-app-pub-3940256099942544/5224354917"
const TEST_INTERSTITIAL := "ca-app-pub-3940256099942544/1033173712"
const RETRY_S := [5.0, 15.0, 45.0, 120.0]

var _rewarded: RewardedAd = null
var _interstitial: InterstitialAd = null
var _rewarded_loader: RewardedAdLoader
var _interstitial_loader: InterstitialAdLoader
var _ready_sdk := false
var _rewarded_tries := 0
var _interstitial_tries := 0
var _consent: ConsentInformation


func get_backend_name() -> String:
	return "admob"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_consent = UserMessagingPlatform.consent_information
	var params := ConsentRequestParameters.new()
	_consent.update(params, _on_consent_updated, func(_e: FormError) -> void: _start_sdk())


func _on_consent_updated() -> void:
	if _consent.get_is_consent_form_available() and _consent.get_consent_status() == ConsentInformation.ConsentStatus.REQUIRED:
		UserMessagingPlatform.load_consent_form(
			func(form: ConsentForm) -> void: form.show(func(_e: FormError) -> void: _start_sdk()),
			func(_e: FormError) -> void: _start_sdk())
	else:
		_start_sdk()


func _start_sdk() -> void:
	if _ready_sdk:
		return
	var init := OnInitializationCompleteListener.new()
	init.on_initialization_complete = func(_s: InitializationStatus) -> void:
		_ready_sdk = true
		_load_rewarded()
		_load_interstitial()
	MobileAds.initialize(init)


## GDPR: a way to change consent later (Settings shows a button when needed).
func privacy_options_required() -> bool:
	return _consent != null and _consent.get_privacy_options_requirement_status() == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED


func show_privacy_options() -> void:
	UserMessagingPlatform.show_privacy_options_form(func(_e: FormError) -> void: pass)


func _id(key: String, fallback: String) -> String:
	var v := str(ProjectSettings.get_setting("petri/admob/" + key, ""))
	return v if v.begins_with("ca-app-pub-") else fallback


# ------------------------------------------------------------- rewarded

func is_rewarded_ready() -> bool:
	return _rewarded != null


func _load_rewarded() -> void:
	if not _ready_sdk or _rewarded != null:
		return
	_rewarded_loader = RewardedAdLoader.new()
	var cb := RewardedAdLoadCallback.new()
	cb.on_ad_loaded = func(ad: RewardedAd) -> void:
		_rewarded = ad
		_rewarded_tries = 0
	cb.on_ad_failed_to_load = func(err: LoadAdError) -> void:
		Analytics.event("ad_load_failed", {"kind": "rewarded", "code": err.code})
		_retry(_load_rewarded, _rewarded_tries)
		_rewarded_tries += 1
	_rewarded_loader.load(_id("rewarded_id", TEST_REWARDED), AdRequest.new(), cb)


func show_rewarded(placement: String, done: Callable) -> void:
	if _rewarded == null:
		done.call(false)
		_load_rewarded()
		return
	var ad := _rewarded
	_rewarded = null
	var earned := [false]
	var finished := [false]
	var finish := func() -> void:
		if finished[0]:
			return
		finished[0] = true
		ad.destroy()
		done.call(earned[0])
		_load_rewarded()
	var fs := FullScreenContentCallback.new()
	fs.on_ad_dismissed_full_screen_content = finish
	fs.on_ad_failed_to_show_full_screen_content = func(_e: AdError) -> void: finish.call()
	ad.full_screen_content_callback = fs
	ad.on_ad_paid = func(v: AdValue) -> void: _paid("rewarded", placement, v)
	var listener := OnUserEarnedRewardListener.new()
	listener.on_user_earned_reward = func(_item: RewardedItem) -> void: earned[0] = true
	ad.show(listener)


# --------------------------------------------------------- interstitial

func is_interstitial_ready() -> bool:
	return _interstitial != null


func _load_interstitial() -> void:
	if not _ready_sdk or _interstitial != null:
		return
	_interstitial_loader = InterstitialAdLoader.new()
	var cb := InterstitialAdLoadCallback.new()
	cb.on_ad_loaded = func(ad: InterstitialAd) -> void:
		_interstitial = ad
		_interstitial_tries = 0
	cb.on_ad_failed_to_load = func(err: LoadAdError) -> void:
		Analytics.event("ad_load_failed", {"kind": "interstitial", "code": err.code})
		_retry(_load_interstitial, _interstitial_tries)
		_interstitial_tries += 1
	_interstitial_loader.load(_id("interstitial_id", TEST_INTERSTITIAL), AdRequest.new(), cb)


func show_interstitial(placement: String, done: Callable) -> void:
	if _interstitial == null:
		done.call()
		_load_interstitial()
		return
	var ad := _interstitial
	_interstitial = null
	var finished := [false]
	var finish := func() -> void:
		if finished[0]:
			return
		finished[0] = true
		ad.destroy()
		done.call()
		_load_interstitial()
	var fs := FullScreenContentCallback.new()
	fs.on_ad_dismissed_full_screen_content = finish
	fs.on_ad_failed_to_show_full_screen_content = func(_e: AdError) -> void: finish.call()
	ad.full_screen_content_callback = fs
	ad.on_ad_paid = func(v: AdValue) -> void: _paid("interstitial", placement, v)
	ad.show()


# --------------------------------------------------------------- shared

func _retry(again: Callable, tries: int) -> void:
	var wait: float = RETRY_S[mini(tries, RETRY_S.size() - 1)]
	get_tree().create_timer(wait, true, false, true).timeout.connect(again)


## Ad revenue, for ROAS (Firebase in M3 step 3 reads this event).
func _paid(kind: String, placement: String, v: AdValue) -> void:
	Analytics.event("ad_paid", {"kind": kind, "placement": placement, "micros": v.value_micros, "currency": v.currency_code})
