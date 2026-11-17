package pe.familiaprado.app;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import org.springframework.http.MediaType;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@Service
public class ChangeFeed {
    private final List<SseEmitter> listeners = new CopyOnWriteArrayList<>();
    public SseEmitter subscribe() {
        Session.current();
        SseEmitter stream = new SseEmitter(30L * 60 * 1000);
        listeners.add(stream);
        stream.onCompletion(() -> listeners.remove(stream));
        stream.onTimeout(() -> { listeners.remove(stream); stream.complete(); });
        stream.onError(error -> listeners.remove(stream));
        send(stream,"ready","connected");
        return stream;
    }
    public void changed(String topic) {
        if (!List.of("turns", "fund", "appointments", "family").contains(topic))
            throw new IllegalArgumentException("Unknown event topic");
        if (TransactionSynchronizationManager.isActualTransactionActive()
                && TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override public void afterCommit() { broadcast(topic); }
            });
        } else broadcast(topic);
    }
    private void send(SseEmitter stream,String event,String payload) {
        try { stream.send(SseEmitter.event().name(event).data(payload)); }
        catch (Exception ex) { listeners.remove(stream); stream.completeWithError(ex); }
    }
    private void broadcast(String topic) {
        // No health or financial contents are broadcast; each user refetches with their own token.
        for (SseEmitter listener : listeners) send(listener,"changed",topic);
    }
    @Scheduled(fixedDelay = 25000)
    public void heartbeat() {
        for (SseEmitter listener : listeners) send(listener,"heartbeat","ok");
    }
}

@RestController
class ChangeFeedController {
    private final ChangeFeed feed;
    ChangeFeedController(ChangeFeed feed) { this.feed=feed; }
    @GetMapping(value="/api/events",produces=MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter events() { return feed.subscribe(); }
}
