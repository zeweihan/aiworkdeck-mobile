package com.aiworkdeck.mobile

import com.aiworkdeck.mobile.model.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File

/** 契约夹具适配：读取 contract/fixtures 目录下的 JSON 夹具，驱动 Kotlin 领域函数。Gradle 单测工作目录 = 模块目录 android/app。 */
class ContractFixturesTest {
    private fun fixture(name: String): JsonObject =
        Json.parseToJsonElement(File("../../contract/fixtures/$name.json").readText()).jsonObject
    private fun cases(name: String) = fixture(name)["cases"]!!.jsonArray.map { it.jsonObject }
    private fun st(s: String) = TransferState.fromRaw(s) ?: error("unknown state $s")
    private fun item(state: TransferState) = TestItems.make(state)

    @Test fun tally() {
        for (k in cases("tally")) {
            val items = k["states"]!!.jsonArray.map { item(st(it.jsonPrimitive.content)) }
            val t = TransferTally.of(items); val e = k["expect"]!!.jsonObject
            val name = k["name"]!!.jsonPrimitive.content
            assertEquals(name, e["uploading"]!!.jsonPrimitive.int, t.uploading)
            assertEquals(name, e["failed"]!!.jsonPrimitive.int, t.failed)
            assertEquals(name, e["staged"]!!.jsonPrimitive.int, t.staged)
            assertEquals(name, e["landed"]!!.jsonPrimitive.int, t.landed)
            assertEquals(name, e["total"]!!.jsonPrimitive.int, t.total)
        }
    }

    @Test fun transitions() {
        for (k in cases("transitions")) {
            val from = st(k["from"]!!.jsonPrimitive.content)
            val ev = TransferEvent.entries.first { it.raw == k["event"]!!.jsonPrimitive.content }
            val attempts = k["attempts"]!!.jsonPrimitive.int
            val want = k["to"]!!.let { if (it is JsonNull) null else st(it.jsonPrimitive.content) }
            assertEquals("$from+${ev.raw}($attempts)", want, from.next(ev, attempts))
        }
    }

    @Test fun restore() {
        for (k in cases("restore")) {
            assertEquals(st(k["expect"]!!.jsonPrimitive.content),
                st(k["state"]!!.jsonPrimitive.content).recovered(k["attempts"]!!.jsonPrimitive.int))
        }
    }

    @Test fun statusMerge() {
        for (k in cases("status-merge")) {
            val s = k["status"]!!.jsonObject; val e = k["expect"]!!.jsonObject
            val got = st(k["state"]!!.jsonPrimitive.content).applyingStatus(
                delivered = s["delivered"]!!.jsonPrimitive.boolean,
                waitingSeconds = s["waitingSeconds"]!!.jsonPrimitive.long,
                expiresAt = s["expiresAt"]?.jsonPrimitive?.contentOrNull)
            val name = k["name"]!!.jsonPrimitive.content
            assertEquals(name, st(e["state"]!!.jsonPrimitive.content), got.state)
            assertEquals(name, e["waitingSeconds"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.long }, got.waitingSeconds)
            assertEquals(name, e["expiresAt"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.content }, got.expiresAt)
        }
    }

    @Test fun deleteWarning() {
        for (k in cases("delete-warning")) {
            val states = k["states"]!!.jsonArray.map { st(it.jsonPrimitive.content) }
            val e = k["expect"]!!.jsonObject
            val (level, n) = LibraryGrouping.deleteWarningLevel(states)
            assertEquals(e["level"]!!.jsonPrimitive.content, level)
            assertEquals(e["n"]!!.jsonPrimitive.int, n)
        }
    }

    @Test fun legacyMovingDecodes() {
        assertEquals(TransferState.uploading, TransferState.fromRaw("moving"))
        assertEquals("uploading", TransferState.uploading.raw)
    }
}
