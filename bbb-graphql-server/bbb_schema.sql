--unaccent will be used to create nameSortable
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE OR REPLACE FUNCTION immutable_lower_unaccent(text)
				RETURNS text AS $$
				SELECT lower(unaccent('unaccent', $1))
				$$ LANGUAGE SQL IMMUTABLE;

-- ========== Meeting tables

create table "meeting" (
	"meetingId"	varchar(100) primary key,
	"extId" 	varchar(100),
	"name" varchar(100),
	"isBreakout" boolean,
	"disabledFeatures" varchar[],
	"meetingCameraCap" integer,
	"maxPinnedCameras" integer,
	"notifyRecordingIsOn" boolean,
	"presentationUploadExternalDescription" text,
	"presentationUploadExternalUrl" varchar(500),
	"learningDashboardAccessToken" varchar(100),
	"html5InstanceId" varchar(100),
	"logoutUrl" varchar(500),
	"customLogoUrl" varchar(500),
	"bannerText" text,
	"bannerColor" varchar(50),
	"createdTime" bigint,
	"durationInSeconds" integer,
	"endedAt" timestamp with time zone,
	"endedReasonCode" varchar(200),
	"endedBy" varchar(50)
);
ALTER TABLE "meeting" ADD COLUMN "createdAt" timestamp with time zone GENERATED ALWAYS AS (to_timestamp("createdTime"::double precision / 1000)) STORED;
ALTER TABLE "meeting" ADD COLUMN "ended" boolean GENERATED ALWAYS AS ("endedAt" is not null) STORED;

create index "idx_meeting_extId" on "meeting"("extId");

create table "meeting_breakout" (
	"meetingId" 		varchar(100) primary key references "meeting"("meetingId") ON DELETE CASCADE,
    "parentId"           varchar(100),
    "sequence"           integer,
    "freeJoin"           boolean,
    "breakoutRooms"      varchar[],
    "record"             boolean,
    "privateChatEnabled" boolean,
    "captureNotes"       boolean,
    "captureSlides"      boolean,
    "captureNotesFilename" varchar(100),
    "captureSlidesFilename" varchar(100)
);
create index "idx_meeting_breakout_meetingId" on "meeting_breakout"("meetingId");
create view "v_meeting_breakoutPolicies" as select * from meeting_breakout;

create table "meeting_recordingPolicies" (
	"meetingId" 		varchar(100) primary key references "meeting"("meetingId") ON DELETE CASCADE,
	"record" boolean,
	"autoStartRecording" boolean,
	"allowStartStopRecording" boolean,
	"keepEvents" boolean
);
create view "v_meeting_recordingPolicies" as select * from "meeting_recordingPolicies";

create table "meeting_recording" (
	"meetingId" varchar(100) references "meeting"("meetingId") ON DELETE CASCADE,
    "startedAt" timestamp with time zone,
    "startedBy" varchar(50),
    "stoppedAt" timestamp with time zone,
    "stoppedBy" varchar(50),
    "recordedTimeInSeconds" integer,
    CONSTRAINT "meeting_recording_pkey" PRIMARY KEY ("meetingId","startedAt")
);
create index "idx_meeting_recording_meetingId" on "meeting_recording"("meetingId");

--Set recordedTimeInSeconds when stoppedAt is updated
CREATE OR REPLACE FUNCTION "update_meeting_recording_trigger_func"() RETURNS TRIGGER AS $$
BEGIN
    NEW."recordedTimeInSeconds" := CASE WHEN NEW."startedAt" IS NULL OR NEW."stoppedAt" IS NULL THEN 0
                                    ELSE EXTRACT(EPOCH FROM (NEW."stoppedAt" - NEW."startedAt"))
                                    END;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER "update_meeting_recording_trigger" BEFORE UPDATE OF "stoppedAt" ON "meeting_recording"
    FOR EACH ROW EXECUTE FUNCTION "update_meeting_recording_trigger_func"();


--ALTER TABLE "meeting_recording" ADD COLUMN "recordedTimeInSeconds" integer GENERATED ALWAYS AS
--(CASE WHEN "startedAt" IS NULL OR "stoppedAt" IS NULL THEN 0 ELSE EXTRACT(EPOCH FROM ("stoppedAt" - "startedAt")) END) STORED;

CREATE VIEW v_meeting_recording AS
SELECT r.*,
CASE
    WHEN "startedAt" IS NULL THEN false
    WHEN "stoppedAt" IS NULL THEN true
    ELSE "startedAt" > "stoppedAt"
END AS "isRecording"
FROM (
	select "meetingId",
	(array_agg("startedAt" ORDER BY "startedAt" DESC))[1] as "startedAt",
	(array_agg("startedBy" ORDER BY "startedAt" DESC))[1] as "startedBy",
	(array_agg("stoppedAt" ORDER BY "startedAt" DESC))[1] as "stoppedAt",
	(array_agg("stoppedBy" ORDER BY "startedAt" DESC))[1] as "stoppedBy",
    coalesce(sum("recordedTimeInSeconds"),0) "previousRecordedTimeInSeconds"
	from "meeting_recording"
	GROUP BY "meetingId"
) r;

create table "meeting_welcome" (
	"meetingId" varchar(100) primary key references "meeting"("meetingId") ON DELETE CASCADE,
	"welcomeMsgTemplate" text,
	"welcomeMsg" text,
	"welcomeMsgForModerators" text
);
create index "idx_meeting_welcome_meetingId" on "meeting_welcome"("meetingId");

create table "meeting_voice" (
	"meetingId" 		varchar(100) primary key references "meeting"("meetingId") ON DELETE CASCADE,
	"telVoice" varchar(100),
	"voiceConf" varchar(100),
	"dialNumber" varchar(100),
	"muteOnStart" boolean
);
create index "idx_meeting_voice_meetingId" on "meeting_voice"("meetingId");
create view "v_meeting_voiceSettings" as select * from meeting_voice;

create table "meeting_usersPolicies" (
	"meetingId" 		varchar(100) primary key references "meeting"("meetingId") ON DELETE CASCADE,
    "maxUsers"                 integer,
    "maxUserConcurrentAccesses" integer,
    "webcamsOnlyForModerator"  boolean,
    "userCameraCap"            integer,
    "guestPolicy"              varchar(100),
    "guestLobbyMessage"        text,
    "meetingLayout"            varchar(100),
    "allowModsToUnmuteUsers"   boolean,
    "allowModsToEjectCameras"  boolean,
    "authenticatedGuest"       boolean
);
create index "idx_meeting_usersPolicies_meetingId" on "meeting_usersPolicies"("meetingId");

CREATE OR REPLACE VIEW "v_meeting_usersPolicies" AS
SELECT "meeting_usersPolicies"."meetingId",
    "meeting_usersPolicies"."maxUsers",
    "meeting_usersPolicies"."maxUserConcurrentAccesses",
    "meeting_usersPolicies"."webcamsOnlyForModerator",
    "meeting_usersPolicies"."userCameraCap",
    "meeting_usersPolicies"."guestPolicy",
    "meeting_usersPolicies"."guestLobbyMessage",
    "meeting_usersPolicies"."meetingLayout",
    "meeting_usersPolicies"."allowModsToUnmuteUsers",
    "meeting_usersPolicies"."allowModsToEjectCameras",
    "meeting_usersPolicies"."authenticatedGuest",
    "meeting"."isBreakout" is false "moderatorsCanMuteAudio",
    "meeting"."isBreakout" is false and "meeting_usersPolicies"."allowModsToUnmuteUsers" is true "moderatorsCanUnmuteAudio"
   FROM "meeting_usersPolicies"
   JOIN "meeting" using("meetingId");

create table "meeting_lockSettings" (
	"meetingId" 		varchar(100) primary key references "meeting"("meetingId") ON DELETE CASCADE,
    "disableCam"             boolean,
    "disableMic"             boolean,
    "disablePrivateChat"     boolean,
    "disablePublicChat"      boolean,
    "disableNotes"           boolean,
    "hideUserList"           boolean,
    "lockOnJoin"             boolean,
    "lockOnJoinConfigurable" boolean,
    "hideViewersCursor"      boolean,
    "hideViewersAnnotation"  boolean
);
create index "idx_meeting_lockSettings_meetingId" on "meeting_lockSettings"("meetingId");

CREATE OR REPLACE VIEW "v_meeting_lockSettings" AS
SELECT
	mls."meetingId",
	mls."disableCam",
	mls."disableMic",
	mls."disablePrivateChat",
	mls."disablePublicChat",
	mls."disableNotes",
	mls."hideUserList",
	mls."hideViewersCursor",
	mls."hideViewersAnnotation",
	mup."webcamsOnlyForModerator",
	CASE WHEN
	mls."disableCam" IS TRUE THEN TRUE
	WHEN mls."disableMic"  IS TRUE THEN TRUE
	WHEN mls."disablePrivateChat"  IS TRUE THEN TRUE
	WHEN mls."disablePublicChat"  IS TRUE THEN TRUE
	WHEN mls."disableNotes"  IS TRUE THEN TRUE
	WHEN mls."hideUserList"  IS TRUE THEN TRUE
	WHEN mls."hideViewersCursor"  IS TRUE THEN TRUE
	WHEN mls."hideViewersAnnotation"  IS TRUE THEN TRUE
	WHEN mup."webcamsOnlyForModerator"  IS TRUE THEN TRUE
	ELSE FALSE
	END "hasActiveLockSetting"
FROM meeting m
JOIN "meeting_lockSettings" mls ON mls."meetingId" = m."meetingId"
JOIN "meeting_usersPolicies" mup ON mup."meetingId" = m."meetingId";

create table "meeting_clientSettings" (
	"meetingId" 		varchar(100) primary key references "meeting"("meetingId") ON DELETE CASCADE,
    "clientSettingsJson"    jsonb
);

CREATE VIEW "v_meeting_clientSettings" AS SELECT * FROM "meeting_clientSettings";

create view "v_meeting_clientPluginSettings" as
select "meetingId",
       plugin->>'name' as "name",
       plugin->>'url' as "url",
       (plugin->>'settings')::jsonb as "settings",
       (plugin->>'dataChannels')::jsonb as "dataChannels"
from (
    select "meetingId", jsonb_array_elements("clientSettingsJson"->'public'->'plugins') AS plugin
    from "meeting_clientSettings"
) settings;

create table "meeting_group" (
	"meetingId"  varchar(100) references "meeting"("meetingId") ON DELETE CASCADE,
    "groupId"    varchar(100),
    "name"       varchar(100),
    "usersExtId" varchar[],
    CONSTRAINT "meeting_group_pkey" PRIMARY KEY ("meetingId","groupId")
);
create index "idx_meeting_group_meetingId" on "meeting_group"("meetingId");
create view "v_meeting_group" as select * from meeting_group;

-- ========== User tables

CREATE TABLE "user" (
	"userId" varchar(50) NOT NULL PRIMARY KEY,
	"extId" varchar(50),
	"meetingId" varchar(100) references "meeting"("meetingId") ON DELETE CASCADE,
	"name" varchar(255),
	"role" varchar(20),
	"avatar" varchar(500),
	"color" varchar(7),
    "sessionToken" varchar(16),
    "authToken" varchar(16),
    "authed" bool,
    "joined" bool,
    "joinErrorCode" varchar(50),
    "joinErrorMessage" varchar(400),
    "banned" bool,
    "loggedOut" bool,  -- when user clicked Leave meeting button
    "guest" bool, --used for dialIn
    "guestStatus" varchar(50),
    "registeredOn" bigint,
    "excludeFromDashboard" bool,
    "enforceLayout" varchar(50),
    --columns of user state bellow
    "raiseHand" bool default false,
    "raiseHandTime" timestamp with time zone,
    "away" bool default false,
    "awayTime" timestamp with time zone,
	"emoji" varchar,
	"emojiTime" timestamp with time zone,
	"guestStatusSetByModerator" varchar(50) references "user"("userId") ON DELETE SET NULL,
	"guestLobbyMessage" text,
	"mobile" bool,
	"clientType" varchar(50),
	"disconnected" bool default false, -- this is the old leftFlag (that was renamed), set when the user just closed the client
	"expired" bool default false, -- when it is been some time the user is disconnected
	"ejected" bool,
	"ejectReason" varchar(255),
	"ejectReasonCode" varchar(50),
	"ejectedByModerator" varchar(50) references "user"("userId") ON DELETE SET NULL,
	"presenter" bool,
	"pinned" bool,
	"locked" bool,
	"speechLocale" varchar(255),
	"hasDrawPermissionOnCurrentPage" bool default FALSE,
	"echoTestRunningAt" timestamp with time zone
);
CREATE INDEX "idx_user_meetingId" ON "user"("meetingId");
CREATE INDEX "idx_user_extId" ON "user"("meetingId", "extId");

--hasDrawPermissionOnCurrentPage is necessary to improve the performance of the order by of userlist
COMMENT ON COLUMN "user"."hasDrawPermissionOnCurrentPage" IS 'This column is dynamically populated by triggers of tables: user, pres_presentation, pres_page, pres_page_writers';
COMMENT ON COLUMN "user"."disconnected" IS 'This column is set true when the user closes the window or his with the server is over';
COMMENT ON COLUMN "user"."expired" IS 'This column is set true after 10 seconds with disconnected=true';
COMMENT ON COLUMN "user"."loggedOut" IS 'This column is set to true when the user click the button to Leave meeting';


--Virtual columns isDialIn, isModerator, isOnline, isWaiting, isAllowed, isDenied
ALTER TABLE "user" ADD COLUMN "isDialIn" boolean GENERATED ALWAYS AS ("clientType" = 'dial-in-user') STORED;
ALTER TABLE "user" ADD COLUMN "isWaiting" boolean GENERATED ALWAYS AS ("guestStatus" = 'WAIT') STORED;
ALTER TABLE "user" ADD COLUMN "isAllowed" boolean GENERATED ALWAYS AS ("guestStatus" = 'ALLOW') STORED;
ALTER TABLE "user" ADD COLUMN "isDenied" boolean GENERATED ALWAYS AS ("guestStatus" = 'DENY') STORED;

ALTER TABLE "user" ADD COLUMN "registeredAt" timestamp with time zone GENERATED ALWAYS AS (to_timestamp("registeredOn"::double precision / 1000)) STORED;

--Used to sort the Userlist
ALTER TABLE "user" ADD COLUMN "nameSortable" varchar(255) GENERATED ALWAYS AS (immutable_lower_unaccent("name")) STORED;

CREATE INDEX "idx_user_waiting" ON "user"("meetingId") where "isWaiting" is true;

--ALTER TABLE "user" ADD COLUMN "isModerator" boolean GENERATED ALWAYS AS (CASE WHEN "role" = 'MODERATOR' THEN true ELSE false END) STORED;
--ALTER TABLE "user" ADD COLUMN "isOnline" boolean GENERATED ALWAYS AS (CASE WHEN "joined" IS true AND "loggedOut" IS false THEN true ELSE false END) STORED;

-- user (on update emoji, raiseHand or away: set new time)
CREATE OR REPLACE FUNCTION update_user_emoji_time_trigger_func()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW."emoji" <> OLD."emoji" THEN
        IF NEW."emoji" = 'none' or  NEW."emoji" = '' THEN
            NEW."emojiTime" := NULL;
        ELSE
            NEW."emojiTime" := NOW();
        END IF;
    END IF;
    IF NEW."raiseHand" IS DISTINCT FROM OLD."raiseHand" THEN
        IF NEW."raiseHand" is false THEN
            NEW."raiseHandTime" := NULL;
        ELSE
            NEW."raiseHandTime" := NOW();
        END IF;
    END IF;
    IF NEW."away" IS DISTINCT FROM OLD."away" THEN
        IF NEW."away" is false THEN
            NEW."awayTime" := NULL;
        ELSE
            NEW."awayTime" := NOW();
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_user_emoji_time_trigger BEFORE UPDATE OF "emoji" ON "user"
    FOR EACH ROW EXECUTE FUNCTION update_user_emoji_time_trigger_func();


CREATE OR REPLACE VIEW "v_user"
AS SELECT "user"."userId",
    "user"."extId",
    "user"."meetingId",
    "user"."name",
    "user"."nameSortable",
    "user"."avatar",
    "user"."color",
    "user"."away",
    "user"."awayTime",
    "user"."raiseHand",
    "user"."raiseHandTime",
    "user"."emoji",
    "user"."emojiTime",
    "user"."guest",
    "user"."guestStatus",
    "user"."mobile",
    "user"."clientType",
    "user"."isDialIn",
    "user"."role",
    "user"."authed",
    "user"."joined",
    "user"."disconnected",
    "user"."expired",
    "user"."banned",
    "user"."loggedOut",
    "user"."registeredOn",
    "user"."registeredAt",
    "user"."presenter",
    "user"."pinned",
    CASE WHEN "user"."role" = 'MODERATOR' THEN false ELSE "user"."locked" END "locked",
    "user"."speechLocale",
    CASE WHEN "user"."echoTestRunningAt" > current_timestamp - INTERVAL '3 seconds' THEN TRUE ELSE FALSE END "isRunningEchoTest",
    "user"."hasDrawPermissionOnCurrentPage",
    CASE WHEN "user"."role" = 'MODERATOR' THEN true ELSE false END "isModerator",
    CASE WHEN "user"."joined" IS true AND "user"."expired" IS false AND "user"."loggedOut" IS false AND "user"."ejected" IS NOT TRUE THEN true ELSE false END "isOnline"
   FROM "user"
  WHERE "user"."loggedOut" IS FALSE
  AND "user"."expired" IS FALSE
  AND "user"."ejected" IS NOT TRUE
  AND "user"."joined" IS TRUE;

CREATE INDEX "idx_v_user_meetingId" ON "user"("meetingId") 
                where "user"."loggedOut" IS FALSE
                AND "user"."expired" IS FALSE
                AND "user"."ejected" IS NOT TRUE
                and "user"."joined" IS TRUE;

CREATE INDEX "idx_v_user_meetingId_orderByColumns" ON "user"("meetingId","role","raiseHandTime","awayTime","emojiTime","isDialIn","hasDrawPermissionOnCurrentPage","nameSortable","userId")
                where "user"."loggedOut" IS FALSE
                AND "user"."expired" IS FALSE
                AND "user"."ejected" IS NOT TRUE
                and "user"."joined" IS TRUE;

CREATE OR REPLACE VIEW "v_user_current"
AS SELECT "user"."userId",
    "user"."extId",
    "user"."authToken",
    "user"."meetingId",
    "user"."name",
    "user"."nameSortable",
    "user"."avatar",
    "user"."color",
    "user"."away",
    "user"."raiseHand",
    "user"."emoji",
    "user"."guest",
    "user"."guestStatus",
    "user"."mobile",
    "user"."clientType",
    "user"."enforceLayout",
    "user"."isDialIn",
    "user"."role",
    "user"."authed",
    "user"."joined",
    "user"."joinErrorCode",
    "user"."joinErrorMessage",
    "user"."disconnected",
    "user"."expired",
    "user"."ejected",
    "user"."ejectReason",
    "user"."ejectReasonCode",
    "user"."banned",
    "user"."loggedOut",
    "user"."registeredOn",
    "user"."registeredAt",
    "user"."presenter",
    "user"."pinned",
    CASE WHEN "user"."role" = 'MODERATOR' THEN false ELSE "user"."locked" END "locked",
    "user"."speechLocale",
    "user"."hasDrawPermissionOnCurrentPage",
    "user"."echoTestRunningAt",
    CASE WHEN "user"."echoTestRunningAt" > current_timestamp - INTERVAL '3 seconds' THEN TRUE ELSE FALSE END "isRunningEchoTest",
    CASE WHEN "user"."role" = 'MODERATOR' THEN true ELSE false END "isModerator",
    CASE WHEN "user"."joined" IS true AND "user"."expired" IS false AND "user"."loggedOut" IS false AND "user"."ejected" IS NOT TRUE THEN true ELSE false END "isOnline"
   FROM "user";

--This view will be used by Meteor to validate if the provided authToken is valid
--It is temporary while Meteor is not removed
create view "v_user_connection_auth" as
select "meetingId", "userId", "authToken"
from "v_user_current"
where "isOnline" is true;

CREATE OR REPLACE VIEW "v_user_guest" AS
SELECT u."meetingId", u."userId",
u."guestStatus",
u."isWaiting",
rank() OVER (
    PARTITION BY u."meetingId"
    ORDER BY u."registeredOn" ASC, u."userId" ASC
) as "positionInWaitingQueue",
u."isAllowed",
u."isDenied",
COALESCE(NULLIF(u."guestLobbyMessage",''),NULLIF(mup."guestLobbyMessage",'')) AS "guestLobbyMessage"
FROM "user" u
JOIN "meeting_usersPolicies" mup using("meetingId")
where u."guestStatus" = 'WAIT';

--v_user_ref will be used only as foreign key (not possible to fetch this table directly through graphql)
--it is necessary because v_user has some conditions like "lockSettings-hideUserList"
--but viewers still needs to query this users as foreign key of chat, cameras, etc
CREATE OR REPLACE VIEW "v_user_ref"
AS SELECT "user"."userId",
    "user"."extId",
    "user"."meetingId",
    "user"."name",
    "user"."nameSortable",
    "user"."avatar",
    "user"."color",
    "user"."away",
    "user"."raiseHand",
    "user"."emoji",
    "user"."guest",
    "user"."guestStatus",
    "user"."mobile",
    "user"."clientType",
    "user"."isDialIn",
    "user"."role",
    "user"."authed",
    "user"."joined",
    "user"."disconnected",
    "user"."expired",
    "user"."banned",
    "user"."loggedOut",
    "user"."registeredOn",
    "user"."registeredAt",
    "user"."presenter",
    "user"."pinned",
    CASE WHEN "user"."role" = 'MODERATOR' THEN false ELSE "user"."locked" END "locked",
    "user"."speechLocale",
    "user"."hasDrawPermissionOnCurrentPage",
    CASE WHEN "user"."role" = 'MODERATOR' THEN true ELSE false END "isModerator",
    CASE WHEN "user"."joined" IS true AND "user"."expired" IS false AND "user"."loggedOut" IS false AND "user"."ejected" IS NOT TRUE THEN true ELSE false END "isOnline"
   FROM "user";

create table "user_customParameter"(
    "userId" varchar(50) REFERENCES "user"("userId") ON DELETE CASCADE,
	"parameter" varchar(255),
	"value" varchar(255),
	CONSTRAINT "user_customParameter_pkey" PRIMARY KEY ("userId","parameter")
);

CREATE VIEW "v_user_customParameter" AS
SELECT u."meetingId", "user_customParameter".*
FROM "user_customParameter"
JOIN "user" u ON u."userId" = "user_customParameter"."userId";

CREATE VIEW "v_user_welcomeMsgs" AS
SELECT
u."meetingId",
u."userId",
w."welcomeMsg",
CASE WHEN u."role" = 'MODERATOR' THEN w."welcomeMsgForModerators" ELSE NULL END "welcomeMsgForModerators"
FROM "user" u
join meeting_welcome w USING("meetingId");


CREATE TABLE "user_voice" (
	"userId" varchar(50) PRIMARY KEY NOT NULL REFERENCES "user"("userId") ON DELETE CASCADE,
	"voiceUserId" varchar(100),
	"callerName" varchar(100),
	"callerNum" varchar(100),
	"callingWith" varchar(100),
	"joined" boolean,
	"listenOnly" boolean,
	"muted" boolean,
	"spoke" boolean,
	"talking" boolean,
	"floor" boolean,
	"lastFloorTime" varchar(25),
	"voiceConf" varchar(100),
	"voiceConfCallSession" varchar(50),
	"voiceConfClientSession" varchar(10),
	"voiceConfCallState" varchar(30),
	"endTime" bigint,
	"startTime" bigint
);
--CREATE INDEX "idx_user_voice_userId" ON "user_voice"("userId");
-- + 6000 means it will hide after 6 seconds
ALTER TABLE "user_voice" ADD COLUMN "hideTalkingIndicatorAt" timestamp with time zone
GENERATED ALWAYS AS (to_timestamp((COALESCE("endTime","startTime") + 6000) / 1000)) STORED;

ALTER TABLE "user_voice" ADD COLUMN "startedAt" timestamp with time zone
GENERATED ALWAYS AS (to_timestamp("startTime"::double precision / 1000)) STORED;

ALTER TABLE "user_voice" ADD COLUMN "endedAt" timestamp with time zone
GENERATED ALWAYS AS (to_timestamp("endTime"::double precision / 1000)) STORED;

CREATE INDEX "idx_user_voice_userId_talking" ON "user_voice"("userId","talking");
CREATE INDEX "idx_user_voice_userId_hideTalkingIndicatorAt" ON "user_voice"("userId","hideTalkingIndicatorAt");

CREATE OR REPLACE VIEW "v_user_voice" AS
SELECT
	u."meetingId",
	"user_voice" .*,
	greatest(coalesce(user_voice."startTime", 0), coalesce(user_voice."endTime", 0)) AS "lastSpeakChangedAt",
	user_talking."userId" IS NOT NULL "showTalkingIndicator"
FROM "user" u
JOIN "user_voice" ON "user_voice"."userId" = u."userId"
LEFT JOIN "user_voice" user_talking ON (user_talking."userId" = u."userId" and user_talking."talking" IS TRUE)
                                       OR (user_talking."userId" = u."userId" and user_talking."hideTalkingIndicatorAt" > now())
WHERE "user_voice"."joined" is true;



---TEMPORARY MINIMONGO ADAPTER START
alter table "user" add "voiceUpdatedAt" timestamp with time zone;

CREATE OR REPLACE FUNCTION "update_user_voiceUpdatedAt_func"() RETURNS TRIGGER AS $$
BEGIN
  UPDATE "user"
  SET "voiceUpdatedAt" = current_timestamp
  WHERE "userId" = NEW."userId";
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER "update_user_voice_trigger" BEFORE UPDATE ON "user_voice" FOR EACH ROW
EXECUTE FUNCTION "update_user_voiceUpdatedAt_func"();

CREATE TRIGGER "insert_user_voice_trigger" BEFORE INSERT ON "user_voice" FOR EACH ROW
EXECUTE FUNCTION "update_user_voiceUpdatedAt_func"();

CREATE TRIGGER "delete_user_voice_trigger" AFTER DELETE ON "user_voice" FOR EACH ROW
EXECUTE FUNCTION "update_user_voiceUpdatedAt_func"();

CREATE OR REPLACE VIEW "v_user_voice_mongodb_adapter" AS
SELECT
	u."meetingId",
	u."userId",
	u."voiceUpdatedAt",
	"user_voice"."voiceUserId",
	"user_voice"."callerName",
	"user_voice"."callerNum",
	"user_voice"."callingWith",
	"user_voice"."joined",
	"user_voice"."listenOnly",
	"user_voice"."muted",
	"user_voice"."spoke",
	"user_voice"."talking",
	"user_voice"."floor",
	"user_voice"."lastFloorTime",
	"user_voice"."voiceConf",
	"user_voice"."voiceConfCallSession",
	"user_voice"."voiceConfClientSession",
	"user_voice"."voiceConfCallState",
	"user_voice"."endTime",
	"user_voice"."startTime",
	"user_voice"."hideTalkingIndicatorAt",
	"user_voice"."startedAt",
	"user_voice"."endedAt",
	greatest(coalesce(user_voice."startTime", 0), coalesce(user_voice."endTime", 0)) AS "lastSpeakChangedAt",
	user_talking."userId" IS NOT NULL "showTalkingIndicator"
FROM "user" u
LEFT JOIN "user_voice" ON "user_voice"."userId" = u."userId"
LEFT JOIN "user_voice" user_talking ON (user_talking."userId" = u."userId" and user_talking."talking" IS TRUE)
                                       OR (user_talking."userId" = u."userId" and user_talking."hideTalkingIndicatorAt" > now());
---TEMPORARY MINIMONGO ADAPTER END



CREATE TABLE "user_camera" (
	"streamId" varchar(100) PRIMARY KEY,
	"userId" varchar(50) NOT NULL REFERENCES "user"("userId") ON DELETE CASCADE
);
CREATE INDEX "idx_user_camera_userId" ON "user_camera"("userId");

CREATE OR REPLACE VIEW "v_user_camera" AS
SELECT
	u."meetingId",
	"user_camera" .*
FROM "user_camera"
JOIN "user" u ON u."userId" = user_camera."userId";

CREATE TABLE "user_breakoutRoom" (
	"userId" varchar(50) PRIMARY KEY REFERENCES "user"("userId") ON DELETE CASCADE,
	"breakoutRoomId" varchar(100),
	"isDefaultName" boolean,
	"sequence" int,
	"shortName" varchar(100),
	"currentlyInRoom" boolean
);
--CREATE INDEX "idx_user_breakoutRoom_userId" ON "user_breakoutRoom"("userId");

CREATE OR REPLACE VIEW "v_user_breakoutRoom" AS
SELECT
	u."meetingId",
	"user_breakoutRoom" .*
FROM "user_breakoutRoom"
JOIN "user" u ON u."userId" = "user_breakoutRoom"."userId";

CREATE TABLE "user_connectionStatus" (
	"userId" varchar(50) PRIMARY KEY REFERENCES "user"("userId") ON DELETE CASCADE,
	"meetingId" varchar(100) REFERENCES "meeting"("meetingId") ON DELETE CASCADE,
	"connectionAliveAt" timestamp with time zone,
	"userClientResponseAt" timestamp with time zone,
	"networkRttInMs" numeric,
	"applicationRttInMs" numeric,
	"status" varchar(25),
	"statusUpdatedAt" timestamp with time zone
);
create index "idx_user_connectionStatus_meetingId" on "user_connectionStatus"("meetingId");

create view "v_user_connectionStatus" as select * from "user_connectionStatus";

--CREATE TABLE "user_connectionStatusHistory" (
--	"userId" varchar(50) REFERENCES "user"("userId") ON DELETE CASCADE,
--	"applicationRttInMs" numeric,
--	"status" varchar(25),
--	"statusUpdatedAt" timestamp with time zone
--);
--CREATE TABLE "user_connectionStatusHistory" (
--	"userId" varchar(50) REFERENCES "user"("userId") ON DELETE CASCADE,
--	"status" varchar(25),
--	"totalOfOccurrences" integer,
--	"highestNetworkRttInMs" numeric,
--	"highestApplicationRttInMs" numeric,
--	"statusInsertedAt" timestamp with time zone,
--	"statusUpdatedAt" timestamp with time zone,
--	CONSTRAINT "user_connectionStatusHistory_pkey" PRIMARY KEY ("userId","status")
--);

CREATE TABLE "user_connectionStatusMetrics" (
	"userId" varchar(50) REFERENCES "user"("userId") ON DELETE CASCADE,
	"status" varchar(25),
	"occurrencesCount" integer,
	"firstOccurrenceAt" timestamp with time zone,
	"lastOccurrenceAt" timestamp with time zone,
	"lowestNetworkRttInMs" numeric,
    "highestNetworkRttInMs" numeric,
    "lastNetworkRttInMs" numeric,
	"lowestApplicationRttInMs" numeric,
	"highestApplicationRttInMs" numeric,
	"lastApplicationRttInMs" numeric,
	CONSTRAINT "user_connectionStatusMetrics_pkey" PRIMARY KEY ("userId","status")
);

create index "idx_user_connectionStatusMetrics_userId" on "user_connectionStatusMetrics"("userId");

--This function populate rtt, status and the table user_connectionStatusMetrics
CREATE OR REPLACE FUNCTION "update_user_connectionStatus_trigger_func"() RETURNS TRIGGER AS $$
DECLARE
    "newApplicationRttInMs" numeric;
    "newStatus" varchar(25);
BEGIN
	IF NEW."connectionAliveAt" IS NULL OR NEW."userClientResponseAt" IS NULL THEN
		RETURN NEW;
	END IF;
	"newApplicationRttInMs" := (EXTRACT(EPOCH FROM (NEW."userClientResponseAt" - NEW."connectionAliveAt")) * 1000);
	"newStatus" := CASE WHEN COALESCE(NEW."networkRttInMs",0) > 2000 THEN 'critical'
	   					WHEN COALESCE(NEW."networkRttInMs",0) > 1000 THEN 'danger'
	   					WHEN COALESCE(NEW."networkRttInMs",0) > 500 THEN 'warning'
	   					ELSE 'normal' END;
    --Update table user_connectionStatusMetrics
    WITH upsert AS (UPDATE "user_connectionStatusMetrics" SET
    "occurrencesCount" = "user_connectionStatusMetrics"."occurrencesCount" + 1,
    "highestApplicationRttInMs" = GREATEST("user_connectionStatusMetrics"."highestApplicationRttInMs","newApplicationRttInMs"),
    "lowestApplicationRttInMs" = LEAST("user_connectionStatusMetrics"."lowestApplicationRttInMs","newApplicationRttInMs"),
    "lastApplicationRttInMs" = "newApplicationRttInMs",
    "highestNetworkRttInMs" = GREATEST("user_connectionStatusMetrics"."highestNetworkRttInMs",NEW."networkRttInMs"),
    "lowestNetworkRttInMs" = LEAST("user_connectionStatusMetrics"."lowestNetworkRttInMs",NEW."networkRttInMs"),
    "lastNetworkRttInMs" = NEW."networkRttInMs",
    "lastOccurrenceAt" = current_timestamp
    WHERE "userId"=NEW."userId" AND "status"= "newStatus" RETURNING *)
    INSERT INTO "user_connectionStatusMetrics"("userId","status","occurrencesCount", "firstOccurrenceAt",
    "highestApplicationRttInMs", "lowestApplicationRttInMs", "lastApplicationRttInMs",
    "highestNetworkRttInMs", "lowestNetworkRttInMs", "lastNetworkRttInMs")
    SELECT NEW."userId", "newStatus", 1, current_timestamp,
    "newApplicationRttInMs", "newApplicationRttInMs", "newApplicationRttInMs",
    NEW."networkRttInMs", NEW."networkRttInMs", NEW."networkRttInMs"
    WHERE NOT EXISTS (SELECT * FROM upsert);
    --Update networkRttInMs, applicationRttInMs, status, statusUpdatedAt in user_connectionStatus
    UPDATE "user_connectionStatus"
    SET "applicationRttInMs" = "newApplicationRttInMs",
    "status" = "newStatus",
	"statusUpdatedAt" = now()
   	WHERE "userId" = NEW."userId";
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER "update_user_connectionStatus_trigger" AFTER UPDATE OF "userClientResponseAt" ON "user_connectionStatus"
    FOR EACH ROW EXECUTE FUNCTION "update_user_connectionStatus_trigger_func"();

--This function clear userClientResponseAt and applicationRttInMs when connectionAliveAt is updated
CREATE OR REPLACE FUNCTION "update_user_connectionStatus_connectionAliveAt_trigger_func"() RETURNS TRIGGER AS $$
BEGIN
    IF NEW."connectionAliveAt" <> OLD."connectionAliveAt" THEN
    	NEW."userClientResponseAt" := NULL;
    	NEW."applicationRttInMs" := NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER "update_user_connectionStatus_connectionAliveAt_trigger" BEFORE UPDATE OF "connectionAliveAt" ON "user_connectionStatus"
    FOR EACH ROW EXECUTE FUNCTION "update_user_connectionStatus_connectionAliveAt_trigger_func"();


CREATE OR REPLACE VIEW "v_user_connectionStatusReport" AS
SELECT u."meetingId", u."userId",
max(cs."connectionAliveAt") AS "connectionAliveAt",
max(cs."status") AS "currentStatus",
--COALESCE(max(cs."applicationRttInMs"),(EXTRACT(EPOCH FROM (current_timestamp - max(cs."connectionAliveAt"))) * 1000)) AS "applicationRttInMs",
CASE WHEN max(cs."connectionAliveAt") < current_timestamp - INTERVAL '12 seconds' THEN TRUE ELSE FALSE END AS "clientNotResponding",
(array_agg(csm."status" ORDER BY csm."lastOccurrenceAt" DESC))[1] as "lastUnstableStatus",
max(csm."lastOccurrenceAt") AS "lastUnstableStatusAt"
FROM "user" u
JOIN "user_connectionStatus" cs ON cs."userId" = u."userId"
LEFT JOIN "user_connectionStatusMetrics" csm ON csm."userId" = u."userId" AND csm."status" != 'normal'
GROUP BY u."meetingId", u."userId";

CREATE INDEX "idx_user_connectionStatusMetrics_UnstableReport" ON "user_connectionStatusMetrics" ("userId") WHERE "status" != 'normal';


CREATE TABLE "user_graphqlConnection" (
	"graphqlConnectionId" serial PRIMARY KEY,
	"sessionToken" varchar(16),
	"middlewareUID" varchar(36),
	"middlewareConnectionId" varchar(12),
	"establishedAt" timestamp with time zone,
	"closedAt" timestamp with time zone
);

CREATE INDEX "idx_user_graphqlConnectionSessionToken" ON "user_graphqlConnection"("sessionToken");



--ALTER TABLE "user_connectionStatus" ADD COLUMN "applicationRttInMs" NUMERIC GENERATED ALWAYS AS
--(CASE WHEN  "connectionAliveAt" IS NULL OR "userClientResponseAt" IS NULL THEN NULL
--ELSE EXTRACT(EPOCH FROM ("userClientResponseAt" - "connectionAliveAt")) * 1000
--END) STORED;
--
--ALTER TABLE "user_connectionStatus" ADD COLUMN "last" NUMERIC GENERATED ALWAYS AS
--(CASE WHEN  "connectionAliveAt" IS NULL OR "userClientResponseAt" IS NULL THEN NULL
--ELSE EXTRACT(EPOCH FROM ("userClientResponseAt" - "connectionAliveAt")) * 1000
--END) STORED;


--CREATE OR REPLACE VIEW "v_user_connectionStatus" AS
--SELECT u."meetingId", u."userId", uc.status, uc."statusUpdatedAt", uc."connectionAliveAt",
--CASE WHEN "statusUpdatedAt" < current_timestamp - INTERVAL '20 seconds' THEN TRUE ELSE FALSE END AS "clientNotResponding"
--FROM "user" u
--LEFT JOIN "user_connectionStatus" uc ON uc."userId" = u."userId";

CREATE TABLE "user_clientSettings"(
	"userId" varchar(50) PRIMARY KEY REFERENCES "user"("userId") ON DELETE CASCADE,
	"meetingId" varchar(100) references "meeting"("meetingId") ON DELETE CASCADE,
	"userClientSettingsJson" jsonb
);

CREATE INDEX "idx_user_clientSettings_meetingId" ON "user_clientSettings"("meetingId");
CREATE INDEX "idx_user_clientSettings_userId" ON "user_clientSettings"("userId");

create view "v_user_clientSettings" as select * from "user_clientSettings";


CREATE TABLE "user_reaction" (
	"userId" varchar(50) REFERENCES "user"("userId") ON DELETE CASCADE,
	"reactionEmoji" varchar(25),
	"durationInSeconds" integer not null,
	"createdAt" timestamp with time zone not null,
	"expiresAt" timestamp with time zone
);

--Set expiresAt on isert or update user_reaction
CREATE OR REPLACE FUNCTION "update_user_reaction_trigger_func"() RETURNS TRIGGER AS $$
BEGIN
    NEW."expiresAt" := NEW."createdAt" + '1 seconds'::INTERVAL * NEW."durationInSeconds";
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER "update_user_reaction_trigger" BEFORE UPDATE ON "user_reaction"
    FOR EACH ROW EXECUTE FUNCTION "update_user_reaction_trigger_func"();

CREATE TRIGGER "insert_user_reaction_trigger" BEFORE INSERT ON "user_reaction" FOR EACH ROW
EXECUTE FUNCTION "update_user_reaction_trigger_func"();

--ALTER TABLE "user_reaction" ADD COLUMN "expiresAt" timestamp with time zone GENERATED ALWAYS AS ("createdAt" + '1 seconds'::INTERVAL * "durationInSeconds") STORED;

CREATE INDEX "idx_user_reaction_userId_createdAt" ON "user_reaction"("userId", "expiresAt");

CREATE VIEW v_user_reaction AS
SELECT u."meetingId", ur."userId", ur."reactionEmoji", ur."createdAt", ur."expiresAt"
FROM "user" u
JOIN "user_reaction" ur ON u."userId" = ur."userId" AND "expiresAt" > current_timestamp;

CREATE VIEW v_user_reaction_current AS
SELECT u."meetingId", ur."userId", (array_agg(ur."reactionEmoji" ORDER BY ur."expiresAt" DESC))[1] as "reactionEmoji"
FROM "user" u
JOIN "user_reaction" ur ON u."userId" = ur."userId" AND "expiresAt" > current_timestamp
GROUP BY u."meetingId", ur."userId";



create view "v_meeting" as
select "meeting".*,  "user_ended"."name" as "endedByUserName"
from "meeting"
left join "user" "user_ended" on "user_ended"."userId" = "meeting"."endedBy"
;

create view "v_meeting_learningDashboard" as
select "meetingId", "learningDashboardAccessToken"
from "v_meeting";


-- ===================== CHAT TABLES


CREATE TABLE "chat" (
	"chatId"  varchar(100),
	"meetingId" varchar(100) REFERENCES "meeting"("meetingId") ON DELETE CASCADE,
	"access" varchar(20),
	"createdBy" varchar(25),
	CONSTRAINT "chat_pkey" PRIMARY KEY ("chatId","meetingId")
);
CREATE INDEX "idx_chat_meetingId" ON "chat"("meetingId");

CREATE TABLE "chat_user" (
	"chatId" varchar(100),
	"meetingId" varchar(100),
	"userId" varchar(50),
	"lastSeenAt" timestamp with time zone,
	"startedTypingAt" timestamp with time zone,
	"lastTypingAt" timestamp with time zone,
	"visible" boolean,
	CONSTRAINT "chat_user_pkey" PRIMARY KEY ("chatId","meetingId","userId"),
    CONSTRAINT chat_fk FOREIGN KEY ("chatId", "meetingId") REFERENCES "chat"("chatId", "meetingId") ON DELETE CASCADE
);

CREATE INDEX "idx_chat_user_chatId" ON "chat_user"("meetingId", "userId", "chatId") WHERE "visible" is true;


--TRIGER startedTypingAt
CREATE OR REPLACE FUNCTION "update_chat_user_startedTypingAt_trigger_func"() RETURNS TRIGGER AS $$
BEGIN
    NEW."startedTypingAt" := CASE WHEN NEW."lastTypingAt" IS NULL THEN NULL
                                  WHEN OLD."lastTypingAt" IS NULL THEN NEW."lastTypingAt"
                                  WHEN OLD."lastTypingAt" < NEW."lastTypingAt" - INTERVAL '5 seconds' THEN NEW."lastTypingAt"
                                  ELSE OLD."startedTypingAt"
                             END;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER "update_chat_user_startedTypingAt_trigger" BEFORE UPDATE OF "lastTypingAt" ON "chat_user"
    FOR EACH ROW EXECUTE FUNCTION "update_chat_user_startedTypingAt_trigger_func"();


create view "v_chat_user" as select * from "chat_user";

CREATE INDEX "idx_chat_user_typing_public" ON "chat_user"("meetingId", "lastTypingAt")
        WHERE "chatId" = 'MAIN-PUBLIC-GROUP-CHAT'
        AND "lastTypingAt" is not null;

CREATE INDEX "idx_chat_user_typing_private" ON "chat_user"("meetingId", "userId", "chatId", "lastTypingAt")
        WHERE "chatId" != 'MAIN-PUBLIC-GROUP-CHAT'
        AND "visible" is true;

CREATE INDEX "idx_chat_with_user_typing_private" ON "chat_user"("meetingId", "userId", "chatId", "lastTypingAt")
        WHERE "chatId" != 'MAIN-PUBLIC-GROUP-CHAT'
        AND "lastTypingAt" is not null;

CREATE OR REPLACE VIEW "v_user_typing_public" AS
SELECT "meetingId", "chatId", "userId", "lastTypingAt", "startedTypingAt",
CASE WHEN "lastTypingAt" > current_timestamp - INTERVAL '5 seconds' THEN true ELSE false END AS "isCurrentlyTyping"
FROM chat_user
WHERE "chatId" = 'MAIN-PUBLIC-GROUP-CHAT'
AND "lastTypingAt" is not null;

CREATE OR REPLACE VIEW "v_user_typing_private" AS
SELECT chat_user."meetingId", chat_user."chatId", chat_user."userId" as "queryUserId", chat_with."userId", chat_with."lastTypingAt", chat_with."startedTypingAt",
CASE WHEN chat_with."lastTypingAt" > current_timestamp - INTERVAL '5 seconds' THEN true ELSE false END AS "isCurrentlyTyping"
FROM chat_user
LEFT JOIN "chat_user" chat_with ON chat_with."meetingId" = chat_user."meetingId"
									AND chat_with."userId" != chat_user."userId"
									AND chat_with."chatId" = chat_user."chatId"
									AND chat_with."lastTypingAt" is not null
WHERE chat_user."chatId" != 'MAIN-PUBLIC-GROUP-CHAT'
AND chat_user."visible" is true;

CREATE TABLE "chat_message" (
	"messageId" varchar(100) PRIMARY KEY,
	"chatId" varchar(100),
	"meetingId" varchar(100),
	"correlationId" varchar(100),
	"chatEmphasizedText" boolean,
	"message" text,
	"messageType" varchar(50),
	"messageMetadata" text,
    "senderId" varchar(100),
    "senderName" varchar(255),
	"senderRole" varchar(20),
	"createdAt" timestamp with time zone,
    CONSTRAINT chat_fk FOREIGN KEY ("chatId", "meetingId") REFERENCES "chat"("chatId", "meetingId") ON DELETE CASCADE
);
CREATE INDEX "idx_chat_message_chatId" ON "chat_message"("chatId","meetingId");

CREATE OR REPLACE FUNCTION "update_chatUser_clear_lastTypingAt_trigger_func"() RETURNS TRIGGER AS $$
BEGIN
  UPDATE "chat_user"
  SET "lastTypingAt" = null
  WHERE "chatId" = NEW."chatId" AND "meetingId" = NEW."meetingId" AND "userId" = NEW."senderId";
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER "update_chatUser_clear_lastTypingAt_trigger" AFTER INSERT ON chat_message FOR EACH ROW
EXECUTE FUNCTION "update_chatUser_clear_lastTypingAt_trigger_func"();


CREATE OR REPLACE VIEW "v_chat" AS
SELECT 	"user"."userId",
        case when "user"."userId" = "chat"."createdBy" then true else false end "amIOwner",
		chat."meetingId",
		chat."chatId",
		cu."visible",
		chat_with."userId" AS "participantId",
		count(DISTINCT cm."messageId") "totalMessages",
		sum(CASE WHEN cm."senderId" != "user"."userId"
		    and cm."createdAt" < current_timestamp - '2 seconds'::interval --set a delay while user send lastSeenAt
		    and cm."createdAt" > coalesce(cu."lastSeenAt","user"."registeredAt") THEN 1 ELSE 0 end) "totalUnread",
		cu."lastSeenAt",
		CASE WHEN chat."access" = 'PUBLIC_ACCESS' THEN true ELSE false end public
FROM "user"
LEFT JOIN "chat_user" cu ON cu."meetingId" = "user"."meetingId" AND cu."userId" = "user"."userId"
--now it will always add chat_user for public chat onUserJoin
--JOIN "chat" ON "user"."meetingId" = chat."meetingId" AND (cu."chatId" = chat."chatId" OR chat."chatId" = 'MAIN-PUBLIC-GROUP-CHAT')
JOIN "chat" ON "user"."meetingId" = chat."meetingId" AND cu."chatId" = chat."chatId"
LEFT JOIN "chat_user" chat_with ON chat_with."meetingId" = chat."meetingId" AND chat_with."chatId" = chat."chatId" AND chat."chatId" != 'MAIN-PUBLIC-GROUP-CHAT' AND chat_with."userId" != cu."userId"
LEFT JOIN chat_message cm ON cm."meetingId" = chat."meetingId" AND cm."chatId" = chat."chatId"
WHERE cu."visible" is true
GROUP BY "user"."userId", chat."meetingId", chat."chatId", cu."visible", cu."lastSeenAt", chat_with."userId";

CREATE OR REPLACE VIEW "v_chat_message_public" AS
SELECT cm.*
FROM chat_message cm
WHERE cm."chatId" = 'MAIN-PUBLIC-GROUP-CHAT';

CREATE OR REPLACE VIEW "v_chat_message_private" AS
SELECT cu."userId",
        cm.*
FROM chat_message cm
JOIN chat_user cu ON cu."meetingId" = cm."meetingId" AND cu."chatId" = cm."chatId"
WHERE cm."chatId" != 'MAIN-PUBLIC-GROUP-CHAT';



--============ Presentation / Annotation


CREATE TABLE "pres_presentation" (
	"presentationId" varchar(100) PRIMARY KEY,
	"meetingId" varchar(100) REFERENCES "meeting"("meetingId") ON DELETE CASCADE,
	"uploadUserId" varchar(100),
    "uploadTemporaryId" varchar(100), --generated by UI
    "uploadToken" varchar(100), --generated by Akka-apps, used for upload POST
	"name" varchar(500),
	"filenameConverted" varchar(500),
	"isDefault" boolean,
	"current" boolean,
	"removable" boolean,
	"downloadable" boolean,
	"downloadFileExtension" varchar(25),
	"downloadFileUri" varchar(500),
    "uploadInProgress" boolean,
    "uploadCompleted" boolean,
    "uploadErrorMsgKey" varchar(100),
    "uploadErrorDetailsJson" jsonb,
    "totalPages" integer,
    "exportToChatStatus" varchar(25),
    "exportToChatCurrentPage" integer,
    "exportToChatHasError" boolean,
    "createdAt" timestamp with time zone DEFAULT now()
);
CREATE INDEX "idx_pres_presentation_meetingId" ON "pres_presentation"("meetingId");
CREATE INDEX "idx_pres_presentation_meetingId_curr" ON "pres_presentation"("meetingId") where "current" is true;
CREATE INDEX "idx_pres_presentation_meetingId_uploadUserId" ON "pres_presentation"("meetingId","uploadUserId");

CREATE TABLE "pres_page" (
	"pageId" varchar(100) PRIMARY KEY,
	"presentationId" varchar(100) REFERENCES "pres_presentation"("presentationId") ON DELETE CASCADE,
	"num" integer,
	"urlsJson" jsonb,
	"content" TEXT,
	"slideRevealed" boolean default false,
	"current" boolean,
	"xOffset" NUMERIC,
	"yOffset" NUMERIC,
	"widthRatio" NUMERIC,
	"heightRatio" NUMERIC,
    "width" NUMERIC,
    "height" NUMERIC,
    "viewBoxWidth" NUMERIC,
    "viewBoxHeight" NUMERIC,
    "maxImageWidth" integer,
    "maxImageHeight" integer,
    "uploadCompleted" boolean
);
CREATE INDEX "idx_pres_page_presentationId" ON "pres_page"("presentationId");
CREATE INDEX "idx_pres_page_presentationId_curr" ON "pres_page"("presentationId") where "current" is true;

CREATE OR REPLACE VIEW public.v_pres_presentation AS
SELECT pres_presentation."meetingId",
	pres_presentation."presentationId",
	pres_presentation."name",
	pres_presentation."filenameConverted",
	pres_presentation."isDefault",
	pres_presentation."current",
	pres_presentation."downloadable",
	pres_presentation."downloadFileExtension",
	pres_presentation."downloadFileUri",
	pres_presentation."removable",
    pres_presentation."uploadTemporaryId",
    pres_presentation."uploadInProgress",
    pres_presentation."uploadCompleted",
    pres_presentation."totalPages",
    (   SELECT count(*)
        FROM pres_page
        WHERE pres_page."presentationId" = pres_presentation."presentationId"
        AND "uploadCompleted" is true
    ) as "totalPagesUploaded",
    pres_presentation."uploadErrorMsgKey",
    pres_presentation."uploadErrorDetailsJson",
    case when pres_presentation."exportToChatStatus" is not null
                and pres_presentation."exportToChatStatus" != 'EXPORTED'
                and pres_presentation."exportToChatHasError" is not true
                then true else false end "exportToChatInProgress",
    pres_presentation."exportToChatStatus",
    pres_presentation."exportToChatCurrentPage",
    pres_presentation."exportToChatHasError",
    pres_presentation."createdAt"
   FROM pres_presentation;

CREATE OR REPLACE VIEW public.v_pres_page AS
SELECT pres_presentation."meetingId",
	pres_page."presentationId",
	pres_page."pageId",
    pres_page.num,
    pres_page."urlsJson",
    pres_page.content,
    pres_page."slideRevealed",
    CASE WHEN pres_presentation."current" IS TRUE AND pres_page."current" IS TRUE THEN true ELSE false END AS "isCurrentPage",
    pres_page."xOffset",
    pres_page."yOffset" ,
    pres_page."widthRatio",
    pres_page."heightRatio",
    pres_page."width",
    pres_page."height",
    pres_page."viewBoxWidth",
    pres_page."viewBoxHeight",
    (pres_page."width" * LEAST(pres_page."maxImageWidth" / pres_page."width", pres_page."maxImageHeight" / pres_page."height")) AS "scaledWidth",
    (pres_page."height" * LEAST(pres_page."maxImageWidth" / pres_page."width", pres_page."maxImageHeight" / pres_page."height")) AS "scaledHeight",
    (pres_page."width" * pres_page."widthRatio" / 100 * LEAST(pres_page."maxImageWidth" / pres_page."width", pres_page."maxImageHeight" / pres_page."height")) AS "scaledViewBoxWidth",
    (pres_page."height" * pres_page."heightRatio" / 100 * LEAST(pres_page."maxImageWidth" / pres_page."width", pres_page."maxImageHeight" / pres_page."height")) AS "scaledViewBoxHeight",
    pres_page."uploadCompleted"
FROM pres_page
JOIN pres_presentation ON pres_presentation."presentationId" = pres_page."presentationId";

CREATE OR REPLACE VIEW public.v_pres_page_curr AS
SELECT pres_presentation."meetingId",
	pres_page."presentationId",
	pres_page."pageId",
    pres_presentation."name" as "presentationName",
    pres_presentation."filenameConverted" as "presentationFilenameConverted",
    pres_presentation."isDefault" as "isDefaultPresentation",
	pres_presentation."downloadable",
	case when pres_presentation."downloadable" then pres_presentation."downloadFileExtension" else null end "downloadFileExtension",
	case when pres_presentation."downloadable" then pres_presentation."downloadFileUri" else null end "downloadFileUri",
    pres_presentation."removable",
    pres_presentation."totalPages",
    pres_page.num,
    pres_page."urlsJson",
    pres_page.content,
    pres_page."slideRevealed",
    CASE WHEN pres_presentation."current" IS TRUE AND pres_page."current" IS TRUE THEN true ELSE false END AS "isCurrentPage",
    pres_page."xOffset",
    pres_page."yOffset" ,
    pres_page."widthRatio",
    pres_page."heightRatio",
    pres_page."width",
    pres_page."height",
    pres_page."viewBoxWidth",
    pres_page."viewBoxHeight",
    (pres_page."width" * LEAST(pres_page."maxImageWidth" / pres_page."width", pres_page."maxImageHeight" / pres_page."height")) AS "scaledWidth",
    (pres_page."height" * LEAST(pres_page."maxImageWidth" / pres_page."width", pres_page."maxImageHeight" / pres_page."height")) AS "scaledHeight",
    (pres_page."width" * pres_page."widthRatio" / 100 * LEAST(pres_page."maxImageWidth" / pres_page."width", pres_page."maxImageHeight" / pres_page."height")) AS "scaledViewBoxWidth",
    (pres_page."height" * pres_page."heightRatio" / 100 * LEAST(pres_page."maxImageWidth" / pres_page."width", pres_page."maxImageHeight" / pres_page."height")) AS "scaledViewBoxHeight"
FROM pres_presentation
JOIN pres_page ON pres_presentation."presentationId" = pres_page."presentationId" AND pres_page."current" IS TRUE
and pres_presentation."current" IS TRUE;

CREATE TABLE "pres_annotation" (
	"annotationId" varchar(100) PRIMARY KEY,
	"pageId" varchar(100) REFERENCES "pres_page"("pageId") ON DELETE CASCADE,
	"userId" varchar(50),
	"annotationInfo" TEXT,
	"lastHistorySequence" integer,
	"lastUpdatedAt" timestamp with time zone DEFAULT now()
);
CREATE INDEX "idx_pres_annotation_pageId" ON "pres_annotation"("pageId");
CREATE INDEX "idx_pres_annotation_updatedAt" ON "pres_annotation"("pageId","lastUpdatedAt");

CREATE TABLE "pres_annotation_history" (
	"sequence" serial PRIMARY KEY,
	"annotationId" varchar(100),
	"pageId" varchar(100) REFERENCES "pres_page"("pageId") ON DELETE CASCADE,
	"userId" varchar(50),
	"annotationInfo" TEXT
--	"lastUpdatedAt" timestamp with time zone DEFAULT now()
);
CREATE INDEX "idx_pres_annotation_history_pageId" ON "pres_annotation"("pageId");

CREATE VIEW "v_pres_annotation_curr" AS
SELECT p."meetingId", pp."presentationId", pa.*
FROM pres_presentation p
JOIN pres_page pp ON pp."presentationId" = p."presentationId"
JOIN pres_annotation pa ON pa."pageId" = pp."pageId"
WHERE p."current" IS true
AND pp."current" IS true;

CREATE VIEW "v_pres_annotation_history_curr" AS
SELECT p."meetingId", pp."presentationId", pah.*
FROM pres_presentation p
JOIN pres_page pp ON pp."presentationId" = p."presentationId"
JOIN pres_annotation_history pah ON pah."pageId" = pp."pageId"
WHERE p."current" IS true
AND pp."current" IS true;

CREATE TABLE "pres_page_writers" (
	"pageId" varchar(100)  REFERENCES "pres_page"("pageId") ON DELETE CASCADE,
    "userId" varchar(50) REFERENCES "user"("userId") ON DELETE CASCADE,
    "changedModeOn" bigint,
    CONSTRAINT "pres_page_writers_pkey" PRIMARY KEY ("pageId","userId")
);
create index "idx_pres_page_writers_userID" on "pres_page_writers"("userId");

CREATE OR REPLACE VIEW "v_pres_page_writers" AS
SELECT
	u."meetingId",
	"pres_presentation"."presentationId",
	"pres_page_writers" .*,
	CASE WHEN pres_presentation."current" IS true AND pres_page."current" IS true THEN true ELSE false END AS "isCurrentPage"
FROM "pres_page_writers"
JOIN "user" u ON u."userId" = "pres_page_writers"."userId"
JOIN "pres_page" ON "pres_page"."pageId" = "pres_page_writers"."pageId"
JOIN "pres_presentation" ON "pres_presentation"."presentationId"  = "pres_page"."presentationId" ;

CREATE OR REPLACE VIEW "v_pres_presentation_uploadToken" AS
SELECT "meetingId", "presentationId", "uploadUserId", "uploadTemporaryId", "uploadToken"
FROM pres_presentation pp
WHERE "uploadInProgress" IS FALSE
AND "uploadCompleted" IS FALSE;

------------------------------------------------------------
-- Triggers to automatically control "user" flag "hasDrawPermissionOnCurrentPage"

CREATE OR REPLACE FUNCTION "update_user_hasDrawPermissionOnCurrentPage"("p_userId" varchar DEFAULT NULL, "p_meetingId" varchar DEFAULT NULL)
RETURNS VOID AS $$
DECLARE
    where_clause TEXT := '';
BEGIN
    IF "p_userId" IS NOT NULL THEN
        where_clause := format(' AND "userId" = %L', "p_userId");
    END IF;
    IF "p_meetingId" IS NOT NULL THEN
        where_clause := format('%s AND "meetingId" = %L', where_clause, "p_meetingId");
    END IF;

    IF where_clause <> '' THEN
        where_clause := substring(where_clause from 6);
        EXECUTE format('UPDATE "user"
						SET "hasDrawPermissionOnCurrentPage" =
						CASE WHEN presenter THEN TRUE
						WHEN EXISTS (
							SELECT 1 FROM "v_pres_page_writers" v
							WHERE v."userId" = "user"."userId"
							AND v."isCurrentPage" IS TRUE
						) THEN TRUE
						ELSE FALSE
						END  WHERE %s', where_clause);
    ELSE
        RAISE EXCEPTION 'No params provided';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- user (on update presenter)
CREATE OR REPLACE FUNCTION update_user_presenter_trigger_func() RETURNS TRIGGER AS $$
BEGIN
    IF OLD."presenter" <> NEW."presenter" THEN
        PERFORM "update_user_hasDrawPermissionOnCurrentPage"(NEW."userId", NULL);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_user_presenter_trigger AFTER UPDATE OF "presenter" ON "user"
FOR EACH ROW EXECUTE FUNCTION update_user_presenter_trigger_func();

-- pres_presentation (on update current)
CREATE OR REPLACE FUNCTION update_pres_presentation_current_trigger_func() RETURNS TRIGGER AS $$
BEGIN
    IF OLD."current" <> NEW."current" THEN
    	PERFORM "update_user_hasDrawPermissionOnCurrentPage"(NULL, NEW."meetingId");
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_pres_presentation_current_trigger AFTER UPDATE OF "current" ON "pres_presentation"
FOR EACH ROW EXECUTE FUNCTION update_pres_presentation_current_trigger_func();

-- pres_page (on update current)
CREATE OR REPLACE FUNCTION update_pres_page_current_trigger_func()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD."current" <> NEW."current" THEN
    	PERFORM "update_user_hasDrawPermissionOnCurrentPage"(NULL, pres_presentation."meetingId")
        FROM pres_presentation
        WHERE "presentationId" = NEW."presentationId";
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_pres_page_current_trigger AFTER UPDATE OF "current" ON "pres_page"
FOR EACH ROW EXECUTE FUNCTION update_pres_page_current_trigger_func();

-- pres_page_writers (on insert, update or delete)
CREATE OR REPLACE FUNCTION ins_upd_del_pres_page_writers_trigger_func()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' or TG_OP = 'INSERT' THEN
        PERFORM "update_user_hasDrawPermissionOnCurrentPage"(NEW."userId", NULL);
    ELSIF TG_OP = 'DELETE' THEN
        PERFORM "update_user_hasDrawPermissionOnCurrentPage"(OLD."userId", NULL);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER ins_upd_del_pres_page_writers_trigger AFTER INSERT OR UPDATE OR DELETE ON "pres_page_writers"
FOR EACH ROW EXECUTE FUNCTION ins_upd_del_pres_page_writers_trigger_func();

------------------------------------------------------------



CREATE TABLE "pres_page_cursor" (
	"pageId" varchar(100)  REFERENCES "pres_page"("pageId") ON DELETE CASCADE,
    "userId" varchar(50) REFERENCES "user"("userId") ON DELETE CASCADE,
    "xPercent" numeric,
    "yPercent" numeric,
    "lastUpdatedAt" timestamp with time zone DEFAULT now(),
    CONSTRAINT "pres_page_cursor_pkey" PRIMARY KEY ("pageId","userId")
);
create index "idx_pres_page_cursor_pageId" on "pres_page_cursor"("pageId");
create index "idx_pres_page_cursor_userID" on "pres_page_cursor"("userId");
create index "idx_pres_page_cursor_lastUpdatedAt" on "pres_page_cursor"("pageId","lastUpdatedAt");

CREATE VIEW "v_pres_page_cursor" AS
SELECT pres_presentation."meetingId", pres_page."presentationId", c.*,
        CASE WHEN pres_presentation."current" IS true AND pres_page."current" IS true THEN true ELSE false END AS "isCurrentPage"
FROM pres_page_cursor c
JOIN pres_page ON pres_page."pageId" = c."pageId"
JOIN pres_presentation ON pres_presentation."presentationId" = pres_page."presentationId";


-------------------------------------------------------------------
---- Polls

CREATE TABLE "poll" (
"pollId" varchar(100) PRIMARY KEY,
"meetingId" varchar(100) REFERENCES "meeting"("meetingId") ON DELETE CASCADE,
"ownerId" varchar(100) REFERENCES "user"("userId"),
"questionText" TEXT,
"type" varchar(30),
"secret" boolean,
"multipleResponses" boolean,
"ended" boolean,
"published" boolean,
"publishedAt" timestamp with time zone,
"createdAt" timestamp with time zone not null default current_timestamp
);
CREATE INDEX "idx_poll_meetingId" ON "poll"("meetingId");
CREATE INDEX "idx_poll_meetingId_active" ON "poll"("meetingId") where ended is false;
CREATE INDEX "idx_poll_meetingId_published" ON "poll"("meetingId") where published is true;

CREATE TABLE "poll_option" (
	"pollId" varchar(100) REFERENCES "poll"("pollId") ON DELETE CASCADE,
	"optionId" integer,
	"optionDesc" TEXT,
	CONSTRAINT "poll_option_pkey" PRIMARY KEY ("pollId", "optionId")
);
CREATE INDEX "idx_poll_option_pollId" ON "poll_option"("pollId");

CREATE TABLE "poll_response" (
	"pollId" varchar(100),
	"optionId" integer,
	"userId" varchar(100) REFERENCES "user"("userId") ON DELETE CASCADE,
	FOREIGN KEY ("pollId", "optionId") REFERENCES "poll_option"("pollId", "optionId") ON DELETE CASCADE
);
CREATE INDEX "idx_poll_response_pollId" ON "poll_response"("pollId");
CREATE INDEX "idx_poll_response_userId" ON "poll_response"("userId");
CREATE INDEX "idx_poll_response_pollId_userId" ON "poll_response"("pollId", "userId");

CREATE OR REPLACE VIEW "v_poll_response" AS
SELECT
poll."meetingId",
poll."pollId",
poll."type",
poll."questionText",
poll."ownerId" AS "pollOwnerId",
poll.published,
o."optionId",
o."optionDesc",
count(r."optionId") AS "optionResponsesCount",
sum(count(r."optionId")) OVER (partition by poll."pollId") "pollResponsesCount"
FROM poll
JOIN poll_option o ON o."pollId" = poll."pollId"
LEFT JOIN poll_response r ON r."pollId" = poll."pollId" AND o."optionId" = r."optionId"
GROUP BY poll."pollId", o."optionId", o."optionDesc"
ORDER BY poll."pollId";

CREATE VIEW "v_poll_user" AS
SELECT
poll."meetingId",
poll."pollId",
poll."type",
poll."questionText",
poll."ownerId" AS "pollOwnerId",
u."userId",
array_remove(array_agg(o."optionId"), NULL) AS "optionIds",
array_remove(array_agg(o."optionDesc"), NULL) AS "optionDescIds",
CASE WHEN count(o."optionId") > 0 THEN TRUE ELSE FALSE end responded
FROM poll
JOIN v_user u ON u."meetingId" = poll."meetingId" AND "isDialIn" IS FALSE AND presenter IS FALSE
LEFT JOIN poll_response r ON r."pollId" = poll."pollId" AND r."userId" = u."userId"
LEFT JOIN poll_option o ON o."pollId" = r."pollId" AND o."optionId" = r."optionId"
GROUP BY poll."pollId", u."userId", u.name ;

CREATE VIEW "v_poll" AS SELECT * FROM "poll";

CREATE VIEW v_poll_option AS
SELECT poll."meetingId", poll."pollId", o."optionId", o."optionDesc"
FROM poll_option o
JOIN poll using("pollId")
WHERE poll."type" != 'R-';

create view "v_poll_user_current" as
select "user"."userId", "poll"."pollId", case when count(pr.*) > 0 then true else false end as responded
from "user"
join "poll" on "poll"."meetingId" = "user"."meetingId"
left join "poll_response" pr on pr."userId" = "user"."userId" and pr."pollId" = "poll"."pollId"
group by "user"."userId", "poll"."pollId";

--------------------------------
----External video

create table "externalVideo"(
"externalVideoId" varchar(100) primary key,
"meetingId" varchar(100) REFERENCES "meeting"("meetingId") ON DELETE CASCADE,
"externalVideoUrl" varchar(500),
"startedSharingAt" timestamp with time zone,
"stoppedSharingAt" timestamp with time zone,
"updatedAt" timestamp with time zone,
"playerPlaybackRate" numeric,
"playerCurrentTime" numeric,
"playerPlaying" boolean
);
create index "externalVideo_meetingId_current" on "externalVideo"("meetingId") WHERE "stoppedSharingAt" IS NULL;

CREATE VIEW "v_externalVideo" AS
SELECT * FROM "externalVideo"
WHERE "stoppedSharingAt" IS NULL;

--------------------------------
----Screenshare


create table "screenshare"(
"screenshareId" varchar(50) primary key,
"meetingId" varchar(100) REFERENCES "meeting"("meetingId") ON DELETE CASCADE,
"voiceConf" varchar(50),
"screenshareConf" varchar(50),
"contentType" varchar(50),
"stream" varchar(100),
"vidWidth" integer,
"vidHeight" integer,
"hasAudio" boolean,
"startedAt" timestamp with time zone,
"stoppedAt" timestamp with time zone

);
create index "screenshare_meetingId" on "screenshare"("meetingId");
create index "screenshare_meetingId_current" on "screenshare"("meetingId") WHERE "stoppedAt" IS NULL;

CREATE VIEW "v_screenshare" AS
SELECT * FROM "screenshare"
WHERE "stoppedAt" IS NULL;

--------------------------------
----Timer

CREATE TABLE "timer" (
	"meetingId" varchar(100) PRIMARY KEY REFERENCES "meeting"("meetingId") ON DELETE CASCADE,
	"stopwatch" boolean,
	"running" boolean,
	"active" boolean,
	"time" bigint,
	"accumulated" bigint,
	"startedOn" bigint,
	"endedOn" bigint,
	"songTrack" varchar(50)
);

ALTER TABLE "timer" ADD COLUMN "startedAt" timestamp with time zone GENERATED ALWAYS AS (to_timestamp("startedOn"::double precision / 1000)) STORED;
ALTER TABLE "timer" ADD COLUMN "endedAt" timestamp with time zone GENERATED ALWAYS AS (to_timestamp("endedOn"::double precision / 1000)) STORED;

CREATE OR REPLACE VIEW "v_timer" AS
SELECT
     "meetingId",
     "stopwatch",
     case
        when "stopwatch" is true or "running" is false then "running"
        when "startedAt" + (("time" - coalesce("accumulated",0)) * interval '1 milliseconds') >= current_timestamp then true else false
     end "running",
     "active",
     "time",
     "accumulated",
     "startedAt",
     "startedOn",
     "endedAt",
     "endedOn",
     "songTrack"
 FROM "timer";

------------------------------------
----breakoutRoom


CREATE TABLE "breakoutRoom" (
	"breakoutRoomId" varchar(100) NOT NULL PRIMARY KEY,
	"parentMeetingId" varchar(100) REFERENCES "meeting"("meetingId") ON DELETE CASCADE,
	"externalId" varchar(100),
	"sequence" numeric,
	"name" varchar(100),
	"shortName" varchar(100),
	"isDefaultName" bool,
	"freeJoin" bool,
	"startedAt" timestamp with time zone,
	"endedAt" timestamp with time zone,
	"durationInSeconds" int4,
	"sendInvitationToModerators" bool,
	"captureNotes" bool,
	"captureSlides" bool
);

CREATE INDEX "idx_breakoutRoom_parentMeetingId" ON "breakoutRoom"("parentMeetingId", "externalId");

CREATE TABLE "breakoutRoom_user" (
	"breakoutRoomId" varchar(100) NOT NULL REFERENCES "breakoutRoom"("breakoutRoomId") ON DELETE CASCADE,
	"userId" varchar(50) NOT NULL REFERENCES "user"("userId") ON DELETE CASCADE,
	"joinURL" text,
	"assignedAt" timestamp with time zone,
	"joinedAt" timestamp with time zone,
	"inviteDismissedAt" timestamp with time zone,
	CONSTRAINT "breakoutRoom_user_pkey" PRIMARY KEY ("breakoutRoomId", "userId")
);

CREATE OR REPLACE VIEW "v_breakoutRoom" AS
SELECT *,
    --showInvitation flag
    case WHEN 1=1
    	--this is not the last room the user joined
    	-- AND "lastRoomJoinedId" != "breakoutRoomId" --the next condition turn this one useless
    	--user didn't joined some room after assigned
    	AND ("lastRoomJoinedAt" IS NULL OR "lastRoomJoinedAt" < "assignedAt")
    	--user didn't close the invitation already
    	and ("inviteDismissedAt" is NULL OR "assignedAt" > "inviteDismissedAt")
    	--user is not online in other room
    	AND "lastRoomIsOnline" IS FALSE
    	--this is this the last assignment?
    	AND "currentRoomPriority" = 1
    	--user is not moderator or sendInviteToMod flag is true
    	AND ("isModerator" is false OR "sendInvitationToModerators")
    	THEN TRUE ELSE FALSE END "showInvitation"
from (
    SELECT u."userId", b."parentMeetingId", b."breakoutRoomId", b."freeJoin", b."sequence", b."name", b."isDefaultName",
            b."shortName", b."startedAt", b."endedAt", b."durationInSeconds", b."sendInvitationToModerators",
                bu."assignedAt", bu."joinURL", bu."inviteDismissedAt", u."role" = 'MODERATOR' as "isModerator",
                --CASE WHEN b."durationInSeconds" = 0 THEN NULL ELSE b."startedAt" + b."durationInSeconds" * '1 second'::INTERVAL END AS "willEndAt",
                ub."isOnline" AS "currentRoomIsOnline",
                ub."registeredAt" AS "currentRoomRegisteredAt",
                ub."joined" AS "currentRoomJoined",
                rank() OVER (partition BY u."userId" order by "assignedAt" desc nulls last) as "currentRoomPriority",
                max(bu."joinedAt") OVER (partition BY u."userId") AS "lastRoomJoinedAt",
                max(bu."breakoutRoomId") OVER (partition BY u."userId" ORDER BY bu."joinedAt") AS "lastRoomJoinedId",
                sum(CASE WHEN ub."isOnline" THEN 1 ELSE 0 END) OVER (partition BY u."userId") > 0 as "lastRoomIsOnline"
    FROM "user" u
    JOIN "breakoutRoom" b ON b."parentMeetingId" = u."meetingId"
    LEFT JOIN "breakoutRoom_user" bu ON bu."userId" = u."userId" AND bu."breakoutRoomId" = b."breakoutRoomId"
    LEFT JOIN "meeting" mb ON mb."extId" = b."externalId"
    LEFT JOIN "v_user" ub ON ub."meetingId" = mb."meetingId" and ub."extId" = u."extId" || '-' || b."sequence"
    WHERE (bu."assignedAt" IS NOT NULL
            OR b."freeJoin" IS TRUE
            OR u."role" = 'MODERATOR')
    AND b."endedAt" IS NULL
) a;

CREATE OR REPLACE VIEW "v_breakoutRoom_assignedUser" AS
SELECT "parentMeetingId", "breakoutRoomId", "userId"
FROM "v_breakoutRoom"
WHERE "assignedAt" IS NOT NULL;

--TODO improve performance (and handle two users with same extId)
CREATE OR REPLACE VIEW "v_breakoutRoom_participant" AS
SELECT DISTINCT "parentMeetingId", "breakoutRoomId", "userId"
FROM "v_breakoutRoom"
WHERE "currentRoomIsOnline" IS TRUE;
--SELECT DISTINCT br."parentMeetingId", br."breakoutRoomId", "user"."userId"
--FROM v_user "user"
--JOIN "meeting" m using("meetingId")
--JOIN "v_meeting_breakoutPolicies" vmbp using("meetingId")
--JOIN "breakoutRoom" br ON br."parentMeetingId" = vmbp."parentId" AND br."externalId" = m."extId";

--User to update "inviteDismissedAt" via Mutation
CREATE OR REPLACE VIEW "v_breakoutRoom_user" AS
SELECT bu.*
FROM "breakoutRoom_user" bu
where bu."breakoutRoomId" in (
    select b."breakoutRoomId"
    from "user" u
    join "breakoutRoom" b on b."parentMeetingId" = u."meetingId" and b."endedAt" is null
    where u."userId" = bu."userId"
);

------------------------------------
----sharedNotes

create table "sharedNotes" (
    "meetingId" varchar(100) references "meeting"("meetingId") ON DELETE CASCADE,
    "sharedNotesExtId" varchar(25),
    "padId" varchar(25),
    "model" varchar(25),
    "name" varchar(25),
    "pinned" boolean,
    constraint "pk_sharedNotes" primary key ("meetingId", "sharedNotesExtId")
);

create table "sharedNotes_rev" (
	"meetingId" varchar(100) references "meeting"("meetingId") ON DELETE CASCADE,
	"sharedNotesExtId" varchar(25),
	"rev" integer,
	"userId" varchar(50) references "user"("userId") ON DELETE SET NULL,
	"changeset" text,
	"start" integer,
	"end" integer,
	"diff" TEXT,
	"createdAt" timestamp with time zone,
	constraint "pk_sharedNotes_rev" primary key ("meetingId", "sharedNotesExtId", "rev")
);
--create view "v_sharedNotes_rev" as select * from "sharedNotes_rev";

create view "v_sharedNotes_diff" as
select "meetingId", "sharedNotesExtId", "userId", "start", "end", "diff", "rev"
from "sharedNotes_rev"
where "diff" is not null;

create table "sharedNotes_session" (
    "meetingId" varchar(100) references "meeting"("meetingId") ON DELETE CASCADE,
    "sharedNotesExtId" varchar(25),
    "userId" varchar(50) references "user"("userId") ON DELETE CASCADE,
    "sessionId" varchar(50),
    constraint "pk_sharedNotes_session" primary key ("meetingId", "sharedNotesExtId", "userId")
);
create index "sharedNotes_session_userId" on "sharedNotes_session"("userId");

create view "v_sharedNotes" as
SELECT sn.*, max(snr.rev) "lastRev"
FROM "sharedNotes" sn
LEFT JOIN "sharedNotes_rev" snr ON snr."meetingId" = sn."meetingId" AND snr."sharedNotesExtId" = sn."sharedNotesExtId"
GROUP BY sn."meetingId", sn."sharedNotesExtId";

create view "v_sharedNotes_session" as
SELECT sns.*, sn."padId"
FROM "sharedNotes_session" sns
JOIN "sharedNotes" sn ON sn."meetingId" = sns."meetingId" AND sn."sharedNotesExtId" = sn."sharedNotesExtId";

----------------------

CREATE OR REPLACE VIEW "v_current_time" AS
SELECT
	current_timestamp AS "currentTimestamp",
	FLOOR(EXTRACT(EPOCH FROM current_timestamp) * 1000)::bigint AS "currentTimeMillis";

------------------------------------
----audioCaption

CREATE TABLE "caption" (
    "captionId" varchar(100) NOT NULL PRIMARY KEY,
    "meetingId" varchar(100) NOT NULL REFERENCES "meeting"("meetingId") ON DELETE CASCADE,
    "captionType" varchar(100) NOT NULL, --Audio Transcription or Typed Caption
    "userId" varchar(50) REFERENCES "user"("userId") ON DELETE CASCADE,
    "lang" varchar(15),
    "captionText" text,
    "createdAt" timestamp with time zone
);

create index idx_caption on caption("meetingId","lang","createdAt");
create index idx_caption_captionType on caption("meetingId","lang","captionType","createdAt");

CREATE OR REPLACE VIEW "v_caption" AS
SELECT *
FROM "caption"
WHERE "createdAt" > current_timestamp - INTERVAL '5 seconds';

------------------------------------
----

CREATE TABLE "layout" (
	"meetingId" 			varchar(100) primary key references "meeting"("meetingId") ON DELETE CASCADE,
	"currentLayoutType"     varchar(100),
	"presentationMinimized" boolean,
	"cameraDockIsResizing"	boolean,
	"cameraDockPlacement" 	varchar(100),
	"cameraDockAspectRatio" numeric,
	"cameraWithFocus" 		varchar(100),
	"propagateLayout" 		boolean,
	"updatedAt" 			timestamp with time zone
);

CREATE VIEW "v_layout" AS
SELECT * FROM "layout";


--------------------------------
---Plugins Data Channel
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE "pluginDataChannelMessage" (
	"meetingId" varchar(100) references "meeting"("meetingId") ON DELETE CASCADE,
	"pluginName" varchar(255),
	"dataChannel" varchar(255),
	"messageId" varchar(50) DEFAULT uuid_generate_v4(),
	"payloadJson" jsonb,
	"fromUserId" varchar(50) REFERENCES "user"("userId") ON DELETE CASCADE,
	"toRoles" varchar[], --MODERATOR, VIEWER, PRESENTER
	"toUserIds" varchar[],
	"createdAt" timestamp with time zone DEFAULT current_timestamp,
	"deletedAt" timestamp with time zone,
	CONSTRAINT "pluginDataChannel_pkey" PRIMARY KEY ("meetingId","pluginName","dataChannel","messageId")
);

create index "idx_pluginDataChannelMessage_dataChannel" on "pluginDataChannelMessage"("meetingId", "pluginName", "dataChannel", "toRoles", "toUserIds", "createdAt") where "deletedAt" is null;
create index "idx_pluginDataChannelMessage_roles" on "pluginDataChannelMessage"("meetingId", "toRoles", "toUserIds", "createdAt") where "deletedAt" is null;

CREATE OR REPLACE VIEW "v_pluginDataChannelMessage" AS
SELECT u."meetingId", u."userId", m."pluginName", m."dataChannel", m."messageId", m."payloadJson", m."fromUserId", m."toRoles", m."createdAt"
FROM "user" u
JOIN "pluginDataChannelMessage" m ON m."meetingId" = u."meetingId"
			AND ((m."toRoles" IS NULL AND m."toUserIds" IS NULL)
				OR u."userId" = ANY(m."toUserIds")
				OR u."role" = ANY(m."toRoles")
				OR (u."presenter" AND 'PRESENTER' = ANY(m."toRoles"))
				)
WHERE "deletedAt" is null
ORDER BY m."createdAt";

------------------------


create view "v_meeting_componentsFlags" as
select "meeting"."meetingId",
        exists (
            select 1
            from "breakoutRoom"
            where "breakoutRoom"."parentMeetingId" = "meeting"."meetingId"
            and "endedAt" is null
        ) as "hasBreakoutRoom",
        exists (
            select 1
            from "poll"
            where "poll"."meetingId" = "meeting"."meetingId"
            and "ended" is false
            and "published" is false
        ) as "hasPoll",
        exists (
            select 1
            from "timer"
            where "timer"."meetingId" = "meeting"."meetingId"
            and "active" is true
        ) as "hasTimer",
        exists (
            select 1
            from "v_screenshare"
            where "v_screenshare"."meetingId" = "meeting"."meetingId"
        ) as "hasScreenshare",
        exists (
            select 1
            from "v_externalVideo"
            where "v_externalVideo"."meetingId" = "meeting"."meetingId"
        ) as "hasExternalVideo",
        exists (
            select 1
            from "v_user"
            where "v_user"."meetingId" = "meeting"."meetingId"
            and NULLIF("speechLocale",'') is not null
        ) or exists (
            select 1
            from "sharedNotes"
            where "sharedNotes"."meetingId" = "meeting"."meetingId"
            and "model" = 'captions'
        ) as "hasCaption"
from "meeting";
