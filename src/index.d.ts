interface SafeBadges {
	HasBadges: (this: void, player: Player, badgeIds: Array<number>) => { [badgeId: number]: boolean };
	AwardBadges: (
		this: void,
		player: Player,
		badgeIds: Array<number>,
	) => { [badgeId: number]: Array<boolean | string> };
	SetFastFlag: <K extends keyof SafeBadgesFastFlags>(this: void, FastFlag: K, value: SafeBadgesFastFlags[K]) => void;
}

interface SafeBadgesFastFlags {
	ATTEMPT_LIMIT: number;
	RETRY_DELAY: number;
	BACKOFF_FACTOR: number;
	DEBUG_PRINTS: boolean;
}

declare const SafeBadges: SafeBadges;

export = SafeBadges;
