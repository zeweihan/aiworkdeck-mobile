package com.aiworkdeck.mobile

import com.aiworkdeck.mobile.model.RelayProject
import com.aiworkdeck.mobile.services.ApiError
import com.aiworkdeck.mobile.services.Backend
import com.aiworkdeck.mobile.services.MemorySessionStore
import com.aiworkdeck.mobile.services.Unauthorized
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.File

class BackendTest {
    private lateinit var server: MockWebServer
    private lateinit var session: MemorySessionStore
    private lateinit var backend: Backend

    @Before fun setUp() {
        server = MockWebServer()
        server.start()
        session = MemorySessionStore()
        backend = Backend(server.url("/").toString().trimEnd('/'), session)
    }

    @After fun tearDown() { server.shutdown() }

    @Test fun verifyLoginCodeDecodesEnvelopeAndSavesSession() = runTest {
        server.enqueue(MockResponse().setBody(
            """{"code":0,"data":{"sessionId":"sess-1","isNewUser":true,"user":{"id":1,"username":"u","displayName":"U"}}}"""
        ))

        val result = backend.verifyLoginCode("13800000000", "1234")

        assertEquals("sess-1", result.sessionId)
        assertEquals(true, result.isNewUser)
        assertEquals("U", result.user.displayName)
        assertEquals("sess-1", session.current())
    }

    @Test fun myProjectsDecodesBareArray() = runTest {
        server.enqueue(MockResponse().setBody("""[{"deviceId":"d1","key":"k1","name":"n1"}]"""))

        val projects = backend.myProjects()

        assertEquals(listOf(RelayProject("d1", null, "k1", "n1")), projects)
    }

    @Test fun unauthorizedEnvelopeThrowsAndClearsSession() = runTest {
        session.save("stale-session")
        server.enqueue(MockResponse().setBody("""{"code":4010}"""))

        try {
            backend.myProjects()
            fail("expected Unauthorized")
        } catch (expected: Unauthorized) {
            // expected
        }
        assertNull(session.current())
    }

    @Test fun uploadSendsMultipartFieldsAndSessionHeader() = runTest {
        session.save("sess-2")
        server.enqueue(MockResponse().setBody("""{"code":0,"id":9,"clientMediaId":"c1","delivered":false}"""))
        val file = File.createTempFile("upload", ".jpg").apply { writeBytes(byteArrayOf(1, 2, 3)) }

        val result = backend.upload(file, "d1", "k1", "c1", "photo.jpg", "image", "2026-09-02T00:00:00+08:00") {}

        assertEquals(9L, result.id)
        assertEquals("c1", result.clientMediaId)
        assertFalse(result.delivered)

        val request = server.takeRequest()
        assertEquals("sess-2", request.getHeader("X-Session-Id"))
        val body = request.body.readUtf8()
        for (field in listOf("deviceId", "projectKey", "clientMediaId", "fileName", "mediaType", "capturedAt", "file")) {
            assertTrue("missing multipart field $field", body.contains("name=\"$field\""))
        }
    }

    @Test fun businessErrorThrowsApiErrorWithMessage() = runTest {
        server.enqueue(MockResponse().setBody("""{"code":1,"message":"boom"}"""))

        try {
            backend.sendLoginCode("13800000000")
            fail("expected ApiError")
        } catch (e: ApiError) {
            assertEquals(1, e.code)
            assertEquals("boom", e.message)
        }
    }

    @Test fun mediaStatusJoinsClientMediaIdsIntoQuery() = runTest {
        server.enqueue(MockResponse().setBody(
            """[{"clientMediaId":"a","delivered":true,"waitingSeconds":0},{"clientMediaId":"b","delivered":false,"waitingSeconds":5}]"""
        ))

        val result = backend.mediaStatus(listOf("a", "b"))

        assertEquals(2, result.size)
        val request = server.takeRequest()
        assertEquals("/api/mobile/media/status?clientMediaIds=a,b", request.path)
    }
}
