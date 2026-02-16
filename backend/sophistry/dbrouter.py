import random

class PrimaryReplicaRouter:
    """Route reads to replicas and writes to the primary."""
    replicas = ["replica1", "replica2", "replica3"]

    def db_for_write(self, model, **hints):
        return "default"

    def db_for_read(self, model, **hints):
        if hints.get("use_writer"):
            return "default"
        return random.choice(self.replicas)

    def allow_relation(self, obj1, obj2, **hints):
        return True

    def allow_migrate(self, db, app_label, model_name=None, **hints):
        return db == "default"
