"""Add TestCase.learned_vocab JSONField."""

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("evals", "0001_initial"),
    ]

    operations = [
        migrations.AddField(
            model_name="testcase",
            name="learned_vocab",
            field=models.JSONField(
                blank=True,
                null=True,
                help_text="Auto-learned keywords from prompt + answers. Merged into scoring vocab.",
            ),
        ),
    ]
